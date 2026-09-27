# app/config.py

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # ============================================
    # BASE DE DATOS
    # ============================================
    DB_USER: str = "root"
    DB_PASSWORD: str = ""
    DB_HOST: str = "127.0.0.1"
    DB_PORT: str = "3306"
    DB_NAME: str = "servilift_db"

    # ============================================
    # JWT - sin valor por defecto: se define en .env
    # ============================================
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 720  # 12 h: una jornada de inspección

    # ============================================
    # ARCHIVOS (fotos, firmas, PDFs)
    # ============================================
    STORAGE_DIR: str = "storage"
    MAX_FOTO_MB: int = 15

    # URL pública del frontend para el QR del certificado
    URL_VERIFICACION: str = "http://localhost:8000/verificar"

    @property
    def DATABASE_URL(self) -> str:
        return (
            f"mysql+pymysql://{self.DB_USER}:{self.DB_PASSWORD}"
            f"@{self.DB_HOST}:{self.DB_PORT}/{self.DB_NAME}?charset=utf8mb4"
        )


settings = Settings()
