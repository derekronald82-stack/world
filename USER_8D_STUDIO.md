# Catws Personal 8D Creator

Catws Songs 4.0 adds a user-facing **Create your 8D song** screen.

## User flow

```text
Catws Songs
  -> 8D icon / More
  -> Create your 8D song
  -> Choose MP3/WAV/FLAC/M4A/AAC/OGG
  -> Adjust pan speed / intensity / hall reverb / decay
  -> Create 8D Song
  -> Preview
  -> Download OR Save to Catws
```

### Download

The app asks the backend for a short-lived signed download link and opens it in the device browser. The link expires after about 15 minutes. With S3-compatible storage, the backend redirects to a temporary presigned object URL.

### Save to Catws

`Save to Catws` keeps the generated 8D file in object storage and adds it to the user's **My 8D Songs** list. It is not added to the public admin music catalog.

The user can later:

- play/preview it
- download it again
- delete it from Catws

Generated tracks that are not saved are treated as temporary results; old unsaved items are cleaned when the user returns to the creator.

## Storage behavior

The original file chosen by the user is used only for conversion and is deleted from backend storage after processing. The generated 8D MP3 is stored under `outputs/`.

Database table: `user_8d_creations`

Stored fields include:

- user id
- title
- original filename
- generated output path
- saved-to-Catws flag
- created time

## Audio processing

The V4 processor integrates the HRTF-style circular panning and Schroeder hall-reverb engine from the provided `8d_audio_converter.zip`, then normalizes the generated track to approximately -1 dBFS and exports MP3.

Current controls:

- Pan speed: 0.30–0.70 Hz
- Intensity: 0.0–1.5
- Reverb wet mix: 30–40%
- Reverb decay: 2–3 seconds

FFmpeg is required for decoding/MP3 export and is already installed by the included backend Dockerfile.

## Content note

Users should convert and store audio they created, own, or have permission to use.

## Separate 8D playlists (V5)

Catws now keeps normal music playlists and personal 8D playlists separate.

From **Your Music Library** choose:

1. **Normal Songs** for catalog playlists.
2. **8D Songs** for **My 8D Songs** and **8D Playlists**.

After an 8D creation is saved to Catws, use **Add to 8D playlist** to choose an existing 8D playlist or create a new one. Personal 8D tracks are never added to a normal catalog playlist.
