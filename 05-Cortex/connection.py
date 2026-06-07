from snowflake.snowpark import Session
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization

def load_private_key(path):
    with open(path, "rb") as f:
        private_key = serialization.load_pem_private_key(
            f.read(),
            password=None,
            backend=default_backend()
        )
    return private_key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )

connection_params = {
    "account":      "UTHZAZW-FJ87774",
    "user":         "SEBAUSTIN512",
    "private_key":  load_private_key("/Users/sebastienhenry/.ssh/snowflake/snowflake_rsa_key.p8"),
    "role":         "SYSADMIN",
    "warehouse":    "learning_wh",
    "database":     "snowflake_learning",
    "schema":       "analytics"
}

def get_session():
    return Session.builder.configs(connection_params).create()

if __name__ == "__main__":
    session = get_session()
    print(f"Connected: {session.get_current_database()}.{session.get_current_schema()}")
    print(f"Snowflake version: {session.sql('SELECT CURRENT_VERSION()').collect()[0][0]}")