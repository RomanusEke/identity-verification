import boto3
import os
import json
from datetime import datetime

s3 = boto3.client('s3')
rekognition = boto3.client('rekognition')
dynamodb = boto3.resource('dynamodb')

table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
S3_BUCKET = os.environ['S3_BUCKET']
SIMILARITY_THRESHOLD = float(os.environ.get('SIMILARITY_THRESHOLD', 90))

def lambda_handler(event, context):
    try:
        body = json.loads(event['body'])
        user_id = body['userId']
        source_image_key = body['sourceImageKey']
        target_image_key = body['targetImageKey']
        
        # Download images from S3
        source_image = get_image_from_s3(source_image_key)
        target_image = get_image_from_s3(target_image_key)
        
        # Compare faces using Rekognition
        response = rekognition.compare_faces(
            SourceImage={'Bytes': source_image},
            TargetImage={'Bytes': target_image},
            SimilarityThreshold=SIMILARITY_THRESHOLD
        )
        
        # Process results
        verification_id = str(datetime.now().timestamp())
        result = {
            'similarity': response['FaceMatches'][0]['Similarity'] if response['FaceMatches'] else 0,
            'is_match': len(response['FaceMatches']) > 0
        }
        
        # Store verification result
        table.put_item(Item={
            'userId': user_id,
            'verificationId': verification_id,
            'timestamp': datetime.now().isoformat(),
            'status': 'SUCCESS' if result['is_match'] else 'FAILED',
            'result': result,
            'type': 'FACE_VERIFICATION'
        })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'verificationId': verification_id,
                'isMatch': result['is_match'],
                'similarity': result['similarity']
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