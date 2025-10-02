import os
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

rds = boto3.client('rds', region_name=os.environ['REGION'])
db_instance_id = os.environ['DB_INSTANCE_IDENTIFIER']

def lambda_handler(event, context):
    """
    Start or stop RDS Custom SQL Server instance based on EventBridge schedule.

    Event payload:
    {
        "action": "start" | "stop"
    }
    """
    action = event.get('action', 'unknown')

    logger.info(f"Received action: {action} for DB instance: {db_instance_id}")

    try:
        # Get current instance state
        response = rds.describe_db_instances(DBInstanceIdentifier=db_instance_id)
        instance_state = response['DBInstances'][0]['DBInstanceStatus']
        logger.info(f"Current DB instance state: {instance_state}")

        if action == 'start':
            if instance_state == 'stopped':
                logger.info(f"Starting DB instance: {db_instance_id}")
                rds.start_db_instance(DBInstanceIdentifier=db_instance_id)
                return {
                    'statusCode': 200,
                    'body': f'Started DB instance: {db_instance_id}'
                }
            else:
                logger.info(f"DB instance {db_instance_id} is already in state: {instance_state}")
                return {
                    'statusCode': 200,
                    'body': f'DB instance is already running or in transition: {instance_state}'
                }

        elif action == 'stop':
            if instance_state == 'available':
                logger.info(f"Stopping DB instance: {db_instance_id}")
                rds.stop_db_instance(DBInstanceIdentifier=db_instance_id)
                return {
                    'statusCode': 200,
                    'body': f'Stopped DB instance: {db_instance_id}'
                }
            else:
                logger.info(f"DB instance {db_instance_id} is not available: {instance_state}")
                return {
                    'statusCode': 200,
                    'body': f'DB instance cannot be stopped in current state: {instance_state}'
                }

        else:
            logger.error(f"Unknown action: {action}")
            return {
                'statusCode': 400,
                'body': f'Invalid action: {action}. Must be "start" or "stop".'
            }

    except Exception as e:
        logger.error(f"Error processing action {action}: {str(e)}")
        return {
            'statusCode': 500,
            'body': f'Error: {str(e)}'
        }
