#!/usr/bin/env python3
"""
Prometheus Alertmanager Webhook Receiver for DR Automation
Receives alerts from Prometheus and triggers DR actions
"""

import json
import subprocess
import sys
import os
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading
import logging

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/srv/gitlab-dr/webhook.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/webhook':
            try:
                content_length = int(self.headers['Content-Length'])
                post_data = self.rfile.read(content_length)
                alert_data = json.loads(post_data.decode('utf-8'))

                logger.info(f"Received webhook: {json.dumps(alert_data, indent=2)}")

                # Process alerts
                self.process_alerts(alert_data)

                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"status": "success"}')

            except Exception as e:
                logger.error(f"Error processing webhook: {e}")
                self.send_response(500)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(f'{{"error": "{str(e)}"}}'.encode())
        else:
            self.send_response(404)
            self.end_headers()

    def process_alerts(self, alert_data):
        """Process incoming alerts and trigger appropriate DR actions"""
        alerts = alert_data.get('alerts', [])

        for alert in alerts:
            action = alert.get('labels', {}).get('action', '')
            status = alert.get('status', '')
            alertname = alert.get('labels', {}).get('alertname', '')

            logger.info(f"Processing alert: {alertname}, status: {status}, action: {action}")

            if status == 'firing' and action == 'trigger_dr':
                self.trigger_dr(alertname, alert)
            elif status == 'firing' and action == 'recover_dr':
                self.recover_dr(alertname, alert)

    def trigger_dr(self, alertname, alert):
        """Trigger disaster recovery activation"""
        logger.info(f"Triggering DR for alert: {alertname}")

        # Check if DR is already active
        if os.path.exists('/srv/gitlab-dr/dr-active'):
            logger.info("DR already active, skipping trigger")
            return

        try:
            # Create DR active marker
            with open('/srv/gitlab-dr/dr-active', 'w') as f:
                f.write(f"{datetime.now().isoformat()}\n{alertname}\n")

            # Update status
            with open('/srv/gitlab-dr/status', 'w') as f:
                f.write('dr-active')

            # Send notification
            self.send_dr_notification('dr-activated', f"Pi system down - {alertname}")

            # Log the event
            logger.info(f"DR activated due to: {alertname}")

        except Exception as e:
            logger.error(f"Error triggering DR: {e}")

    def recover_dr(self, alertname, alert):
        """Trigger disaster recovery recovery"""
        logger.info(f"Recovering from DR for alert: {alertname}")

        # Check if DR is active
        if not os.path.exists('/srv/gitlab-dr/dr-active'):
            logger.info("DR not active, skipping recovery")
            return

        try:
            # Run recovery script
            result = subprocess.run(
                ['/srv/gitlab-dr/recover-from-cloud.sh'],
                capture_output=True,
                text=True,
                timeout=300  # 5 minute timeout
            )

            if result.returncode == 0:
                # Remove DR active marker
                os.remove('/srv/gitlab-dr/dr-active')

                # Update status
                with open('/srv/gitlab-dr/status', 'w') as f:
                    f.write('recovered')

                # Send notification
                self.send_dr_notification('recovered', f"Pi system recovered - {alertname}")

                logger.info("DR recovery completed successfully")
            else:
                logger.error(f"DR recovery failed: {result.stderr}")

        except subprocess.TimeoutExpired:
            logger.error("DR recovery timed out")
        except Exception as e:
            logger.error(f"Error during DR recovery: {e}")

    def send_dr_notification(self, status, message):
        """Send DR notification to webhook URL"""
        try:
            webhook_url = os.environ.get('DR_WEBHOOK_URL')
            if not webhook_url:
                logger.warning("DR_WEBHOOK_URL not set, skipping notification")
                return

            import requests

            payload = {
                'status': status,
                'message': message,
                'timestamp': datetime.now().isoformat(),
                'hostname': os.uname().nodename
            }

            response = requests.post(webhook_url, json=payload, timeout=10)
            response.raise_for_status()

            logger.info(f"DR notification sent: {status}")

        except Exception as e:
            logger.error(f"Failed to send DR notification: {e}")

def main():
    """Start the webhook server"""
    port = int(os.environ.get('WEBHOOK_PORT', '8081'))

    server = HTTPServer(('0.0.0.0', port), WebhookHandler)
    logger.info(f"Starting Prometheus webhook receiver on port {port}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down webhook receiver")
        server.shutdown()

if __name__ == '__main__':
    main()
