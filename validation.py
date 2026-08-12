from snowflake.snowpark.functions import col, when

def run_validation(session):
    rules = session.table("VALIDATION_RULES").filter(col("is_active") == True).collect()

    customers_df = session.table("customers")
    status_expr = None

    for rule in rules:
        rule_col = rule["COLUMN_NAME"]
        rule_type = rule["RULE_TYPE"]
        fail_code = rule["FAIL_CODE"]

        if rule_type == "NOT_NULL":
            condition = col(rule_col).is_null()
        elif rule_type == "FORMAT_EMAIL":
            condition = ~col(rule_col).like("%@%")
        else:
            continue

        if status_expr is None:
            status_expr = when(condition, fail_code)
        else:
            status_expr = status_expr.when(condition, fail_code)

    validated_df = customers_df.withColumn("validation_status", status_expr.otherwise("PASS"))

    clean_df = validated_df.filter(col("validation_status") == "PASS")
    rejected_df = validated_df.filter(col("validation_status") != "PASS")

    print("Clean rows:")
    clean_df.show()
    print("Rejected rows:")
    rejected_df.show()

    rejected_df.write.mode("overwrite").save_as_table("customers_rejects")

    return clean_df, rejected_df

if __name__ == "__main__":
    from connection import get_session
    session = get_session()
    run_validation(session)
    session.close()