from app.database import Base, engine
from app.db_migrations import run_startup_migrations


def main() -> None:
    Base.metadata.create_all(bind=engine)
    run_startup_migrations(engine)
    print("Database migrations completed.")


if __name__ == "__main__":
    main()
