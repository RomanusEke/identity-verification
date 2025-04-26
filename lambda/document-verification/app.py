import boto3
import os
import json
from datetime import datetime

s3 = boto3.client('s3')
rekognition = boto3.client('rekognition')
dynamodb = boto3.resource('dynamodb')

table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
S3_BUCKET = os.environ['S3_BUCKET']

def lambda_handler(event, context):
    try:
        body = json.loads(event['body'])
        user_id = body['userId']
        document_key = body['documentKey']
        document_type = body.get('documentType', 'ID')
        
        # Download document from S3
        document_image = get_image_from_s3(document_key)
        
        # Extract text using Rekognition
        response = rekognition.detect_document_text(
            Document={'Bytes': document_image}
        )
        
        # Process detected text
        detected_text = [block['Text'] for block in response['Blocks'] if block['BlockType'] == 'LINE']
        
        # Simple validation (in production, use more sophisticated validation)
        is_valid = validate_document(detected_text, document_type)
        
        # Store verification result
        verification_id = str(datetime.now().timestamp())
        table.put_item(Item={
            'userId': user_id,
            'verificationId': verification_id,
            'timestamp': datetime.now().isoformat(),
            'status': 'SUCCESS' if is_valid else 'FAILED',
            'result': {
                'detectedText': detected_text,
                'isValid': is_valid
            },
            'type': 'DOCUMENT_VERIFICATION'
        })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'verificationId': verification_id,
                'isValid': is_valid,
                'detectedText': detected_text
            })
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_image_from_s3(key):
    response = s3.get_object(Bucket=S3_BUCKET, Key=key)
    return response['Body'].read()

def validate_document(text_lines, document_type):
    # Basic validation logic
    if document_type == 'ID':
        required_fields = ['name', 'date of birth', 'id number']
    elif document_type == 'PASSPORT':
        required_fields = ['passport', 'name', 'nationality']
    else:
        required_fields = []
    
    text = ' '.join(text_lines).lower()
    return all(field.lower() in text for field in required_fields)