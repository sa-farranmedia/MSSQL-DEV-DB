import os
import boto3
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize RDS client
rds = boto3.client('rds')

def start_handler(event, context):
    """
    Start RDS Custom instance.
    Triggered by EventBridge on weekday mornings.
    """
    db_instance_id = os.environ['DB_INSTANCE_ID']

    logger.info(f"Starting RDS instance: {db_instance_id}")

    try:
        # Check current status
        response = rds.describe_db_instances(DBInstanceIdentifier=db_instance_id)
        status = response['DBInstances'][0]['DBInstanceStatus']

        logger.info(f"Current status: {status}")

        if status == 'stopped':
            # Start the instance
            rds.start_db_instance(DBInstanceIdentifier=db_instance_id)
            logger.info(f"Successfully initiated start for {db_instance_id}")
            return {
                'statusCode': 200,
                'body': f'Started RDS instance: {db_instance_id}'
            }
        elif status == 'available':
            logger.info(f"Instance {db_instance_id} is already running")
            return {
                'statusCode': 200,
                'body': f'RDS instance already running: {db_instance_id}'
            }
        else:
            logger.warning(f"Instance {db_instance_id} is in state '{status}', cannot start")
            return {
                'statusCode': 400,
                'body': f'Cannot start instance in state: {status}'
            }

    except Exception as e:
        logger.error(f"Error starting RDS instance: {str(e)}")
        raise

def stop_handler(event, context):
    """
    Stop RDS Custom instance.
    Triggered by EventBridge on weeknights and weekends.
    """
    db_instance_id = os.environ['DB_INSTANCE_ID']

    logger.info(f"Stopping RDS instance: {db_instance_id}")

    try:
        # Check current status
        response = rds.describe_db_instances(DBInstanceIdentifier=db_instance_id)
        status = response['DBInstances'][0]['DBInstanceStatus']

        logger.info(f"Current status: {status}")

        if status == 'available':
            # Stop the instance
            rds.stop_db_instance(DBInstanceIdentifier=db_instance_id)
            logger.info(f"Successfully initiated stop for {db_instance_id}")
            return {
                'statusCode': 200,
                'body': f'Stopped RDS instance: {db_instance_id}'
            }
        elif status == 'stopped':
            logger.info(f"Instance {db_instance_id} is already stopped")
            return {
                'statusCode': 200,
                'body': f'RDS instance already stopped: {db_instance_id}'
            }
        else:
            logger.warning(f"Instance {db_instance_id} is in state '{status}', cannot stop")
            return {
                'statusCode': 400,
                'body': f'Cannot stop instance in state: {status}'
            }

    except Exception as e:
        logger.error(f"Error stopping RDS instance: {str(e)}")
        raise


