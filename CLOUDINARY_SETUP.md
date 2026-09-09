# CATWS SONGS Cloudinary setup

Create a Cloudinary account and configure the FastAPI service with:

```env
STORAGE_BACKEND=cloudinary
CLOUDINARY_CLOUD_NAME=b2stvlkr
CLOUDINARY_API_KEY=
CLOUDINARY_API_SECRET=
```

The API uploads and deletes media server-side. Never put the API secret in
Flutter. UUID public IDs are used in these folders:

- `catws/normal/audio/`
- `catws/normal/covers/`
- `catws/eightd/audio/`
- `catws/eightd/covers/`
- `catws/users/{user_id}/eightd/`

Song rows retain both the secure delivery URL and Cloudinary public ID. New
media is uploaded and committed to PostgreSQL before an old replacement asset
is deleted. If a catalog insert fails, newly uploaded assets are removed.
