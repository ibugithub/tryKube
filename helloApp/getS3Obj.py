import boto3
from botocore.exceptions import ClientError

def download_s3_object(bucket_name, object_key, local_path):
    try:
        s3 = boto3.client('s3')
        s3.download_file(bucket_name, object_key, local_path)
        return True
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        print(f"[S3 ERROR] Code: {error_code}, Message: {error_message}")
        return f"[S3 ERROR] Code: {error_code}, Message: {error_message}"
    except Exception as e:
        print(f"[OTHER ERROR] {str(e)}")
        return f"[OTHER ERROR] {str(e)}"