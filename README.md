Hi, 

Welcome to our Git Repository for your DevOps skills assessment.

To begin:
1. Fork this repository.
2. Complete the tasks as outlined in the provided instructions.
3. Add your work and documentation to your forked repository.
4. Send us a link to your repository or zip and send us the files

Good luck!

# *Part 1: General Questions*
1. How would you implement devops for database - maintain history, releases, version control
2. What is role of promote stage in ci-cd process.
3. Suppose there is an app which stores state in its memory - you want to enable working with multiple instance of this app at the same time with high availability - how will you achieve that?
4. How do you perform a Kubernetes upgrade with zero downtime?


# *Part 2: Kubernetes hands on*

1. **Cluster Setup:**
   - Provision a Kubernetes cluster using a tool like `kubeadm`, `kops`, or `kind`.

2. **Nginx Deployment:**
   - Deploy nginx using helm this chart [nginx Helm](https://github.com/kubernetes/ingress-nginx/blob/main/charts/ingress-nginx).
   - When you will deploy the chart as DaemonSet when not, what are the disatvantage/advantage of that. What will you choose with aws load balancer

3.  **App Deployment:**
    - Deploy Jenkins (can be other app you choose) with helm [Jenkins Helm](https://github.com/jenkinsci/helm-charts/blob/main/charts/jenkins). 
          
3. **Scaling:**
   - Implement horizontal and vertical pod autoscaling for nginx using helm values (in the values file)
   - What is keda for auto scaling, why to use Keda?
     
4. **Networking:**
   - How would you restrict network between apps within the cluster? Write an example.
   - Expose the Jenkins applications using Ingress.

5. **Storage:**
   - Configure Persistent Volumes (PVs) and Persistent Volume Claims (PVCs) for Jenkins

6. **Security:**
   - Implement an example Role-Based Access Control (RBAC) on one of the namespace for example restrict a user from some namespace, 
   - What is the purpose of the of the service account - how can it be useful in scenarios over aws.

