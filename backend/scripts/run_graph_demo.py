"""Run the isolated graph demo without replacing an existing development server."""

import uvicorn

import os

from app.config import Settings
from app.main import create_app

# SURREAL_DATABASE in the shell (not .env) points scripts such as the seeded
# Spaces runner at another database, e.g. the Surreal Cloud one.
settings = Settings(
    database_backend="surreal",
    surreal_database=os.environ.get("SURREAL_DATABASE", "phlio_graph_dev"),
    redis_enabled=True,
    redis_url="redis://127.0.0.1:6379/0",
    redis_namespace="phlio_graph_dev",
    social_video_database="data/phlio_graph_dev_videos.sqlite3",
    messaging_database="data/phlio_graph_dev_messages.sqlite3",
)
if __name__ == "__main__":
    uvicorn.run(create_app(settings), host="0.0.0.0", port=8002)
