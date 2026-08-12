from snowflake.snowpark.functions import col, upper, trim

def run_config_etl(session):
    config_rows = session.table("CONFIG_MASTER").filter(col("is_active") == True).collect()

    source_df = session.table("customers")
    for row in config_rows:
        src_col = row["SOURCE_COLUMN"]
        tgt_col = row["TARGET_COLUMN"]
        transform = row["TRANSFORMATION"]

        if transform == "UPPER":
            source_df = source_df.withColumn(tgt_col, upper(col(src_col)))
        elif transform == "TRIM":
            source_df = source_df.withColumn(tgt_col, trim(col(src_col)))
        elif transform == "NONE":
            source_df = source_df.withColumn(tgt_col, col(src_col))

    source_df.show()
    source_df.write.mode("overwrite").save_as_table("customers_mapped")
    print("Saved to customers_mapped")

    return source_df

if __name__ == "__main__":
    from connection import get_session
    session = get_session()
    run_config_etl(session)
    session.close()