from connection import get_session

session = get_session()
print("Connected:", session)

session.close()