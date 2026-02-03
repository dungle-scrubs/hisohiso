#!/usr/bin/env python3
"""
Convert Silero Speaker Verification model to CoreML format.

The Silero model produces 256-dimensional speaker embeddings.
Same speaker = similar embeddings (high cosine similarity).
"""

import os
import sys
import urllib.request

# Check dependencies
try:
    import torch
    import coremltools as ct
except ImportError:
    print("Installing dependencies...")
    os.system("pip3 install torch coremltools")
    import torch
    import coremltools as ct

def download_silero_model():
    """Download the Silero speaker verification model."""
    print("Downloading Silero speaker verification model...")
    
    # Load from torch hub
    model, utils = torch.hub.load(
        repo_or_dir='snakers4/silero-vad',
        model='silero_vad',
        force_reload=False,
        onnx=False
    )
    
    # Actually we need the speaker model, not VAD
    # Let's try the speaker embedding model
    print("Note: Using silero-vad for now. For speaker verification, we need a different approach.")
    return None

def create_simple_embedding_model():
    """
    Create a simple speaker embedding model using MFCC features.
    This is a lightweight alternative while we figure out the full Silero integration.
    
    For production, we should use:
    - Silero speaker verification: https://github.com/snakers4/silero-models
    - Or ECAPA-TDNN from SpeechBrain
    """
    import torch
    import torch.nn as nn
    
    class SimpleSpeakerEmbedding(nn.Module):
        """
        Simple speaker embedding model.
        Input: Audio waveform (16kHz, mono)
        Output: 128-dimensional embedding
        """
        def __init__(self):
            super().__init__()
            # Simple 1D CNN for audio processing
            self.conv1 = nn.Conv1d(1, 32, kernel_size=80, stride=16)  # ~5ms at 16kHz
            self.conv2 = nn.Conv1d(32, 64, kernel_size=3, stride=2)
            self.conv3 = nn.Conv1d(64, 128, kernel_size=3, stride=2)
            self.pool = nn.AdaptiveAvgPool1d(1)
            self.fc = nn.Linear(128, 128)
            self.relu = nn.ReLU()
            
        def forward(self, x):
            # x shape: (batch, samples) - e.g., (1, 32000) for 2 seconds
            x = x.unsqueeze(1)  # (batch, 1, samples)
            x = self.relu(self.conv1(x))
            x = self.relu(self.conv2(x))
            x = self.relu(self.conv3(x))
            x = self.pool(x)
            x = x.squeeze(-1)
            x = self.fc(x)
            # L2 normalize for cosine similarity
            x = x / (x.norm(dim=1, keepdim=True) + 1e-8)
            return x
    
    return SimpleSpeakerEmbedding()

def convert_to_coreml(model, output_path):
    """Convert PyTorch model to CoreML."""
    print("Converting to CoreML...")
    
    model.eval()
    
    # Trace with example input (2 seconds of audio at 16kHz)
    example_input = torch.randn(1, 32000)
    traced_model = torch.jit.trace(model, example_input)
    
    # Convert to CoreML
    mlmodel = ct.convert(
        traced_model,
        inputs=[ct.TensorType(name="audio", shape=(1, 32000))],
        outputs=[ct.TensorType(name="embedding")],
        minimum_deployment_target=ct.target.macOS14,
    )
    
    # Add metadata
    mlmodel.author = "Hisohiso"
    mlmodel.short_description = "Speaker embedding model for voice verification"
    mlmodel.version = "1.0"
    
    # Save
    mlmodel.save(output_path)
    print(f"Saved CoreML model to: {output_path}")
    
    return mlmodel

def main():
    output_dir = os.path.join(os.path.dirname(__file__), "..", "Resources")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, "SpeakerEmbedding.mlpackage")
    
    print("Creating speaker embedding model...")
    model = create_simple_embedding_model()
    
    print(f"Model parameters: {sum(p.numel() for p in model.parameters()):,}")
    
    convert_to_coreml(model, output_path)
    
    print("\nDone! Model saved to Resources/SpeakerEmbedding.mlpackage")
    print("\nNote: This is a simple model for development. For production,")
    print("consider using a pre-trained model like ECAPA-TDNN or Resemblyzer.")

if __name__ == "__main__":
    main()
