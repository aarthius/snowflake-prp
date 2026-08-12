import os
from dotenv import load_dotenv
from snowflake.snowpark import Session

load_dotenv()

def get_session():
    connection_parameters = {
        "account": os.getenv("SNOWFLAKE_ACCOUNT"),
        "user": os.getenv("SNOWFLAKE_USER"),
        "password": os.getenv("SNOWFLAKE_PASSWORD"),
        "role": "SYSADMIN",
        "warehouse": "COMPUTE_WH",
        "database": "RETAIL_DB",
        "schema": "SALES"
    }
    return Session.builder.configs(connection_parameters).create()