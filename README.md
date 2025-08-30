# OpenVPN Community + OIDC Plugin Docker Image

This repository builds a Docker image for OpenVPN Community Edition with the openvpn-auth-oauth2 
plugin, supporting OIDC authentication. 

The image includes an init.sh which can generate the initial setup files (configs, keys and certs)
which are then uploaded to an S3 bucket, where they can be tweaked as required.  They wil be downloaded and installed on container startup. 

## Setup Instructions

### Prerequisites
- Docker
- An S3 bucket to store the configuration files
- AWS credentials (API keys or IAM Role) with permissions to read and write to the bucket

### Getting started
1. Clone this repository.
3. Generate the initial config and certs:
   ```sh
   OIDCVPN_S3_URI=s3://<bucket name>/openvpn
   docker-compose run --remove-orphans --build oidcvpn /init.sh
   ```
3. Run OpenVPN
   ```sh
   docker-compose run oidcvpn
   ```
   
### Entrypoint Script
The image uses an entrypoint script (`entrypoint.sh`) that:
- Syncs the entire S3 directory specified by `OIDCVPN_S3_URI` to `/etc/openvpn`
- Starts OpenVPN with the downloaded config

### Environment Variables

| Variable              | Description                                                         | Required | Example                                  |
|-----------------------|---------------------------------------------------------------------|----------|------------------------------------------|
| OIDCVPN_S3_URI        | S3 URI to the directory containing all OpenVPN config and key files | Yes      | s3://yourbucket/openvpn                  |
| AWS_ACCESS_KEY_ID     | AWS access key for S3 access (if not using IAM role)                | No       | AKIA...                                  |
| AWS_SECRET_ACCESS_KEY | AWS secret key for S3 access (if not using IAM role)                | No       | wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY |
| AWS_SESSION_TOKEN     | AWS session token for temporary credentials (optional)              | No       | ...                                      |

## Security Notes
- Do not bake sensitive configs or credentials into the image.
- **Prefer IAM roles for ECS tasks for better security and easier credential management.**

## Quick Certificate Generation and S3 Upload (for testing & setup)

For local testing or initial setup, you can generate all required OpenVPN 
certificates, keys, and a default server.conf inside the container, and 
upload them directly to your S3 bucket using the provided script:

```sh
docker run --rm -it -e OIDCVPN_S3_URI=s3://yourbucket/openvpn oidcvpn /init.sh
```

This will:
- Generate ca.crt, server.crt, server.key, dh.pem, ta.key, and a default server.conf in a temporary directory inside the container.
- Upload all these files to your S3 bucket.
- Clean up the temporary directory automatically after completion.

You can then edit server.conf directly in S3 as needed. On container startup, the entrypoint script will automatically download the latest versions from S3.

### Deploying on ECS
1. Run the init.sh script to generate the initial conf and upload to S3.
2. Modify the `server.conf` as required
3. Set the required env vars in your ECS Task Definition
4. On container startup, all files in this S3 directory will be synced to `/etc/openvpn` automatically.
5. OpenVPN will start using `/etc/openvpn/server.conf`.
