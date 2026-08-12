import json
import requests
from snowflake.snowpark.types import StructType, StructField, StringType
from snowflake.snowpark.functions import parse_json, col

def run_api_ingest(session):
    response = requests.get("https://jsonplaceholder.typicode.com/users")
    data = response.json()
    print(f"{len(data)} records fetched")

    json_strings = [json.dumps(record) for record in data]

    schema = StructType([StructField("raw_json", StringType())])
    raw_df = session.create_dataframe([(s,) for s in json_strings], schema=schema)

    variant_df = raw_df.withColumn("raw_json", parse_json(col("raw_json")))
    variant_df.write.mode("overwrite").save_as_table("api_users_raw")

    print("Loaded into api_users_raw")

    result = session.sql("""
        SELECT
            raw_json:name::STRING AS name,
            raw_json:email::STRING AS email,
            raw_json:address.city::STRING AS city,
            raw_json:company.name::STRING AS company_name
        FROM api_users_raw
    """)
    result.show()

    return result

if __name__ == "__main__":
    from connection import get_session
    session = get_session()
    run_api_ingest(session)
    session.close()