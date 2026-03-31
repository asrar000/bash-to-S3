"""
Processor Deployer Script
Deploys specified files and zipped folders to S3 by:
1. Uploading individual files as specified
2. Creating a zip archive of specified folders and files
3. Uploading the zip archive to S3
"""

import os
import sys
import boto3
import zipfile
import tempfile
import logging
from datetime import datetime
from pathlib import Path
from botocore.exceptions import ClientError

from deployer.config import Config

# Setup logging
root_dir = Path(__file__).parent.parent  # vrs-inventory-cron/
current_date = datetime.now().strftime("%Y-%m-%d")  # e.g., 2025-03-25
current_datetime = datetime.now().strftime(
    "%Y-%m-%d_%H-%M-%S"
)  # e.g., 2025-03-25_12-34-56
log_dir = (
    root_dir / "logs" / "deployer" / current_date
)  # vrs-inventory-cron/logs/deployer/2025-03-25
log_dir.mkdir(parents=True, exist_ok=True)  # Create directory if it doesn't exist
log_file = (
    log_dir / f"rcron_processor_deployer_{current_datetime}.log"
)  # e.g., rcron_deployer_2025-03-25_12-34-56.log

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(log_file),  # Write logs to file
        logging.StreamHandler(sys.stdout),  # Also output to console
    ],
)
logger = logging.getLogger("processor_deployer")

# Add the parent directory to sys.path to import config
sys.path.append(str(Path(__file__).parent.parent))


class ProcessorDeployer:
    """Handles deployment of specified files and folders to S3."""

    def __init__(self, bucket=None, prefix=None):
        """Initialize the deployer with S3 bucket and prefix."""
        self.s3_bucket = bucket or Config.S3_BUCKET
        self.prefix = prefix or Config.S3_SCRIPTS_DIR
        self.s3_prefix = f"{self.prefix}/processor"

        # Configure boto3 session with AWS profile
        AWS_PROFILE = "default"
        if Config.AWS_PROFILE != "default":
            AWS_PROFILE = Config.AWS_PROFILE
        session = boto3.Session(profile_name=AWS_PROFILE, region_name=Config.AWS_REGION)
        self.s3_client = session.client("s3")

        self.root_dir = Path(__file__).parent.parent
        self.processor_dir = self.root_dir / "processor"

        # Define files to upload individually (relative to processor_dir)
        self.files_to_upload = [
            "requirements.txt",
            "install-requirements.sh",
            "booking_processor.py",  # Example; adjust as needed
            "vrbo_processor.py",
            "hotelplanner_processor.py",
            "vio_processor.py",
            "holibob_processor.py",
            "general_processor.py",
            "viator_processor.py",
        ]

        # Define items to zip (relative to processor_dir)
        self.items_to_zip = {
            "modules.zip": [  # Output zip name : list of files/folders to include
                "booking",  # Folder
                "vrbo",  # Folder
                "hotelplanner",  # Folder
                "vio",  # Folder
                "general",
                "common",  # Folder
                "holibob",
                "viator",
                "config.py",  # File (optional)
            ]
        }

        logger.info(
            f"Initialized deployer for bucket: {self.s3_bucket},"
            f" prefix: {self.s3_prefix}"
        )

    def upload_file(self, local_path, s3_key):
        """Upload a single file to S3."""
        try:
            if not local_path.exists():
                logger.error(f"File not found: {local_path}")
                return False

            logger.info(f"Uploading {local_path} to s3://{self.s3_bucket}/{s3_key}")
            self.s3_client.upload_file(str(local_path), self.s3_bucket, s3_key)
            self.s3_client.head_object(
                Bucket=self.s3_bucket, Key=s3_key
            )  # Verify upload
            logger.info(f"Successfully uploaded {s3_key}")
            return True

        except ClientError as e:
            logger.error(f"Failed to upload {local_path}: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error uploading {local_path}: {e}")
            return False

    def create_zip(self, zip_name, items, temp_dir):
        """Create a zip file from specified items."""
        zip_path = Path(temp_dir) / zip_name

        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zipf:
            for item in items:
                item_path = self.processor_dir / item
                if not item_path.exists():
                    logger.warning(f"Item not found, skipping: {item_path}")
                    continue
                if item_path.is_dir():
                    for root, _, files in os.walk(item_path):
                        for file in files:
                            file_path = Path(root) / file
                            arcname = file_path.relative_to(self.processor_dir)
                            zipf.write(file_path, arcname)
                else:
                    arcname = item_path.relative_to(self.processor_dir)
                    zipf.write(item_path, arcname)

        logger.info(f"Created zip archive at {zip_path}")
        return zip_path

    def deploy(self):
        """Deploy specified files and zipped folders to S3."""
        try:
            all_successful = True

            # Upload individual files
            for file in self.files_to_upload:
                local_path = self.processor_dir / file
                s3_key = f"{self.s3_prefix}/{file}"
                all_successful &= self.upload_file(local_path, s3_key)

            # Create and upload zip files
            with tempfile.TemporaryDirectory() as temp_dir:
                for zip_name, items in self.items_to_zip.items():
                    zip_path = self.create_zip(zip_name, items, temp_dir)
                    s3_key = f"{self.s3_prefix}/{zip_name}"
                    all_successful &= self.upload_file(zip_path, s3_key)

            if all_successful:
                logger.info("Deployment completed successfully")
                return True
            else:
                logger.error("Deployment failed due to one or more errors")
                return False

        except Exception as e:
            logger.error(f"Deployment failed: {e}")
            return False


if __name__ == "__main__":
    try:
        deployer = ProcessorDeployer()
        success = deployer.deploy()
        sys.exit(0 if success else 1)
    except Exception as e:
        logger.critical(f"Unhandled exception: {e}")
        sys.exit(1)
