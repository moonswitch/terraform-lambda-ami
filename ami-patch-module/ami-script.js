// this file will contain the javascript configs, below is an example from chatGPT
const AWS = require("aws-sdk");

const eks = new AWS.EKS();

exports.handler = async function(event) {
  // Get the current version of the cluster
  const clusterName = process.env.CLUSTER_NAME;
  const clusterResponse = await eks.describeCluster({ name: clusterName }).promise();
  const clusterVersion = clusterResponse.cluster.version;

  // Get the latest version of the AMI
  const amiResponse = await eks.describeNodegroup({
    clusterName: clusterName,
    nodegroupName: "ng-1"
  }).promise();
  const latestAmiVersion = amiResponse.nodegroup.releaseVersion;

  // If the AMI is out of date, update it
  if (clusterVersion !== latestAmiVersion) {
    console.log(`Updating cluster ${clusterName} from version ${clusterVersion} to ${latestAmiVersion}`);
    await eks.updateClusterVersion({
      name: clusterName,
      version: latestAmiVersion
    }).promise();
  } else {
    console.log(`Cluster ${clusterName} is already up to date`);
  }
};

// You will need to specify the name of the cluster in the CLUSTER_NAME environment variable and replace "ng-1" with the name of your node group.