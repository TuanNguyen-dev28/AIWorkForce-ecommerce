import pymysql
from pymysql.connections import Connection

from config.settings import Settings


def connect(settings: Settings, *, select_database: bool = True) -> Connection:
    return pymysql.connect(
        host=settings.database_host,
        port=settings.database_port,
        user=settings.database_user,
        password=settings.database_password.get_secret_value(),
        database=settings.database_name if select_database else None,
        charset="utf8mb4",
        autocommit=True,
        connect_timeout=settings.dependency_timeout_seconds,
        read_timeout=settings.dependency_timeout_seconds,
        write_timeout=settings.dependency_timeout_seconds,
    )
