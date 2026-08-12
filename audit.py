from connection import get_session
from validation import run_validation

def log_pipeline_run(session):
    clean_df, rejected_df = run_validation(session)

    total_count = clean_df.count() + rejected_df.count()
    pass_count = clean_df.count()
    fail_count = rejected_df.count()

    session.sql(f"""
        INSERT INTO PIPELINE_AUDIT_LOG (source_table, records_read, records_passed, records_rejected, status)
        VALUES ('customers', {total_count}, {pass_count}, {fail_count}, 'COMPLETED')
    """).collect()

    print(f"Audit logged: {total_count} read, {pass_count} passed, {fail_count} rejected")

if __name__ == "__main__":
    session = get_session()
    log_pipeline_run(session)
    session.close()