@echo off
cd /d %~dp0

echo 1) Package Lambda into .\lambda\scale_logger.zip
powershell -Command "Compress-Archive -Path lambda\lambda_function.py -DestinationPath lambda\scale_logger.zip -Force"

echo 2) Terraform init
terraform init

echo 3) Terraform validate
terraform validate || exit /b 1

echo 4) Terraform plan
terraform plan -out=tfplan || exit /b 1

echo 5) Terraform apply
terraform apply tfplan

echo Deploy complete!
pause
