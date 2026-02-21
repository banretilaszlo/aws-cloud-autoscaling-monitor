@echo off
cd /d %~dp0

echo Destroying infrastructure...
terraform destroy -auto-approve

echo All resources deleted.
pause
