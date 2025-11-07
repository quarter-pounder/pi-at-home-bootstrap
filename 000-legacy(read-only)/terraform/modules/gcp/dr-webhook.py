"""
Cloud Function to process DR webhooks from Pi
GCP Always Free Tier: 2M invocations/month, 400K GB-seconds compute
"""

import json
import os
import requests
from datetime import datetime
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_webhook(request):
    """
    Process DR webhook from Pi system
    """
    try:
        # Parse the request
        if request.method != 'POST':
            return {'error': 'Method not allowed'}, 405

        # Get the webhook data
        webhook_data = request.get_json()
        if not webhook_data:
            return {'error': 'No JSON data provided'}, 400

        # Extract alert information
        alerts = webhook_data.get('alerts', [])
        if not alerts:
            return {'error': 'No alerts in webhook data'}, 400

        # Process each alert
        for alert in alerts:
            process_alert(alert)

        return {'status': 'success', 'processed': len(alerts)}, 200

    except Exception as e:
        logger.error(f"Error processing webhook: {e}")
        return {'error': 'Internal server error'}, 500

def process_alert(alert):
    """
    Process individual alert from Prometheus
    """
    try:
        alert_name = alert.get('labels', {}).get('alertname', 'unknown')
        action = alert.get('labels', {}).get('action', '')
        status = alert.get('status', 'unknown')

        logger.info(f"Processing alert: {alert_name}, action: {action}, status: {status}")

        # Handle different alert types
        if action == 'trigger_dr':
            handle_dr_trigger(alert)
        elif action == 'recover_dr':
            handle_dr_recovery(alert)
        else:
            logger.warning(f"Unknown action: {action}")

    except Exception as e:
        logger.error(f"Error processing alert: {e}")

def handle_dr_trigger(alert):
    """
    Handle DR trigger event
    """
    try:
        alert_name = alert.get('labels', {}).get('alertname', 'unknown')
        timestamp = datetime.now().isoformat()

        # Log the DR trigger
        logger.info(f"DR TRIGGERED: {alert_name} at {timestamp}")

        # Send notification to external webhook if configured
        webhook_url = os.environ.get('WEBHOOK_URL')
        if webhook_url:
            send_external_notification(webhook_url, {
                'event': 'dr_triggered',
                'alert': alert_name,
                'timestamp': timestamp,
                'message': f'Pi system failure detected: {alert_name}'
            })

        # Store in Cloud Logging for analysis
        logger.info(f"DR_TRIGGER: {json.dumps({
            'alert_name': alert_name,
            'timestamp': timestamp,
            'status': 'triggered'
        })}")

    except Exception as e:
        logger.error(f"Error handling DR trigger: {e}")

def handle_dr_recovery(alert):
    """
    Handle DR recovery event
    """
    try:
        alert_name = alert.get('labels', {}).get('alertname', 'unknown')
        timestamp = datetime.now().isoformat()

        # Log the DR recovery
        logger.info(f"DR RECOVERED: {alert_name} at {timestamp}")

        # Send notification to external webhook if configured
        webhook_url = os.environ.get('WEBHOOK_URL')
        if webhook_url:
            send_external_notification(webhook_url, {
                'event': 'dr_recovered',
                'alert': alert_name,
                'timestamp': timestamp,
                'message': f'Pi system recovered: {alert_name}'
            })

        # Store in Cloud Logging for analysis
        logger.info(f"DR_RECOVERY: {json.dumps({
            'alert_name': alert_name,
            'timestamp': timestamp,
            'status': 'recovered'
        })}")

    except Exception as e:
        logger.error(f"Error handling DR recovery: {e}")

def send_external_notification(webhook_url, data):
    """
    Send notification to external webhook
    """
    try:
        response = requests.post(
            webhook_url,
            json=data,
            timeout=10,
            headers={'Content-Type': 'application/json'}
        )
        response.raise_for_status()
        logger.info(f"External notification sent successfully: {response.status_code}")

    except requests.exceptions.RequestException as e:
        logger.error(f"Failed to send external notification: {e}")
    except Exception as e:
        logger.error(f"Unexpected error sending notification: {e}")

def health_check(request):
    """
    Health check endpoint
    """
    return {
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'service': 'pi-dr-webhook'
    }, 200
