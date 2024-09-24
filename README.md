# Project Outline

## 1. Create a Virtual Machine with the following minimum hardware specifications:

- **CPUs**: 2 vCPUs
- **Memory**: 2 GB RAM
- **Disk Space**: 10 GB
- **Network**: Enabled

### Deployment Details
- **OS**: Deploy the latest Oracle Linux UEK and harden it.
  - Perform a minimal installation of the OS.
  - Apply the recipe from [RHEL9-CIS Ansible Lockdown](https://github.com/ansible-lockdown/RHEL9-CIS) to make it CIS compliant.

### Required Artifacts
- **Playbook Summary**: Document the summary of playbook execution.
- **Kernel Modules Configuration**: 
  - Command: `modprobe -c`
  - Expected Output: Results showing kernel modules configurations.
- **Audit Rules Configuration**: 
  - Command: `auditctl -l`
  - Expected Output: List of all active audit rules.

## 2. Create a Helm Chart to deploy a Prometheus server in a Kubernetes cluster.

### Requirements
- **ConfigMaps**: Prometheus config and rules should be maintained in separate configmaps.
- **Workload Type**: Use a StatefulSet workload for deployment.

### Deployment Process
- Deploy Prometheus initially to the Kubernetes cluster.
- Post-deployment, make required changes in the configmap that contains the Prometheus configuration and update the deployment.
- Provide the Helm Chart configuration files before and after the changes.
### Commands Used: Following are the commands I used to deploy and update this assignment.


