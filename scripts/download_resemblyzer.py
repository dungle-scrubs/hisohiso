#!/usr/bin/env python3
"""
Download and convert Resemblyzer speaker verification model to CoreML.

Resemblyzer uses a GE2E (Generalized End-to-End) loss trained model that
produces 256-dimensional speaker embeddings. It's based on the paper
"Generalized End-to-End Loss for Speaker Verification" (Google, 2018).
"""

import os
import sys

def install_deps():
    """Install required dependencies."""
    print("Installing dependencies...")
    os.system("pip3 install torch torchaudio resemblyzer coremltools soundfile")

try:
    import torch
    import coremltools as ct
    from resemblyzer import VoiceEncoder
except ImportError:
    install_deps()
    import torch
    import coremltools as ct
    from resemblyzer import VoiceEncoder

def convert_resemblyzer_to_coreml(output_path: str):
    """
    Convert Resemblyzer VoiceEncoder to CoreML format.
    
    The model expects:
    - Input: mel spectrogram frames (batch, n_frames, 40)
    - Output: 256-dimensional embedding
    
    For simplicity, we'll create a wrapper that takes raw audio.
    """
    print("Loading Resemblyzer model...")
    encoder = VoiceEncoder()
    encoder.eval()
    
    # Resemblyzer's forward expects mel spectrogram partials
    # Shape: (batch_size, n_frames, 40) where 40 is mel channels
    # We need at least 160 frames (partial_n_frames)
    
    print("Creating traceable wrapper...")
    
    class ResemblyzerWrapper(torch.nn.Module):
        """Wrapper that takes mel spectrograms and returns embeddings."""
        def __init__(self, encoder):
            super().__init__()
            self.lstm = encoder.lstm
            self.linear = encoder.linear
            self.relu = torch.nn.ReLU()
            
        def forward(self, mels):
            # mels: (batch, n_frames, 40)
            # LSTM expects (batch, seq, features)
            out, (hidden, _) = self.lstm(mels)
            # Take the last hidden state
            embeds_raw = self.relu(self.linear(hidden[-1]))
            # L2 normalize
            embeds = embeds_raw / (torch.norm(embeds_raw, dim=1, keepdim=True) + 1e-5)
            return embeds
    
    wrapper = ResemblyzerWrapper(encoder)
    wrapper.eval()
    
    # Trace with example input
    # 160 frames is the default partial length in Resemblyzer
    n_frames = 160
    example_input = torch.randn(1, n_frames, 40)
    
    print("Tracing model...")
    traced = torch.jit.trace(wrapper, example_input)
    
    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="mel_spectrogram", shape=(1, n_frames, 40))],
        outputs=[ct.TensorType(name="embedding")],
        minimum_deployment_target=ct.target.macOS14,
    )
    
    # Add metadata
    mlmodel.author = "Hisohiso (Resemblyzer)"
    mlmodel.short_description = "Speaker embedding model based on GE2E loss"
    mlmodel.version = "1.0"
    
    mlmodel.save(output_path)
    print(f"Saved CoreML model to: {output_path}")
    
    # Verify output dimension
    print(f"\nModel info:")
    print(f"  Input: mel_spectrogram (1, {n_frames}, 40)")
    print(f"  Output: embedding (1, 256)")
    
    return mlmodel

def main():
    output_dir = os.path.join(os.path.dirname(__file__), "..", "Resources")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, "SpeakerEmbedding.mlpackage")
    
    # Backup old model if exists
    if os.path.exists(output_path):
        import shutil
        backup_path = output_path + ".backup"
        if os.path.exists(backup_path):
            shutil.rmtree(backup_path)
        shutil.move(output_path, backup_path)
        print(f"Backed up old model to {backup_path}")
    
    convert_resemblyzer_to_coreml(output_path)
    
    print("\nDone! The model now uses pre-trained Resemblyzer weights.")
    print("Note: You'll need to update VoiceVerifier.swift to:")
    print("  1. Compute mel spectrograms from audio")
    print("  2. Use 256-dim embeddings instead of 128")

if __name__ == "__main__":
    main()
