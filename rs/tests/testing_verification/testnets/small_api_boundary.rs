// Set up a testnet containing:
//   one 1-node System and one 1-node Application subnets, one unassigned node, single boundary node, and a p8s (with grafana) VM.
// All replica nodes use the following resources: 6 vCPUs, 24GiB of RAM, and 50 GiB disk.
//
// You can setup this testnet with a lifetime of 180 mins by executing the following commands:
//
//   $ ./gitlab-ci/tools/docker-run
//   $ ict testnet create small_api_boundary --lifetime-mins=180 --output-dir=./small_api_boundary -- --test_tmpdir=./small_api_boundary
//
// The --output-dir=./small_api_boundary will store the debug output of the test driver in the specified directory.
// The --test_tmpdir=./small_api_boundary will store the remaining test output in the specified directory.
// This is useful to have access to in case you need to SSH into an IC node for example like:
//
//   $ ssh -i small_api_boundary/_tmp/*/setup/ssh/authorized_priv_keys/admin admin@
//
// Note that you can get the  address of the IC node from the ict console output:
//
//   {
//     nodes: [
//       {
//         id: y4g5e-dpl4n-swwhv-la7ec-32ngk-w7f3f-pr5bt-kqw67-2lmfy-agipc-zae,
//         ipv6: 2a0b:21c0:4003:2:5034:46ff:fe3c:e76f
//       }
//     ],
//     subnet_id: 5hv4k-srndq-xgw53-r6ldt-wtv4x-6xvbj-6lvpf-sbu5n-sqied-63bgv-eqe,
//     subnet_type: application
//   },
//
// To get access to P8s and Grafana look for the following lines in the ict console output:
//
//     prometheus: Prometheus Web UI at http://prometheus.small_api_boundary--1692597750709.testnet.farm.dfinity.systems,
//     grafana: Grafana at http://grafana.small_api_boundary--1692597750709.testnet.farm.dfinity.systems,
//     progress_clock: IC Progress Clock at http://grafana.small_api_boundary--1692597750709.testnet.farm.dfinity.systems/d/ic-progress-clock/ic-progress-clock?refresh=10su0026from=now-5mu0026to=now,
//
// Happy testing!

use anyhow::Result;

use ic_registry_subnet_type::SubnetType;
use ic_tests::driver::{
    api_boundary_node::{ApiBoundaryNode, ApiBoundaryNodeVm},
    group::SystemTestGroup,
    ic::{InternetComputer, Subnet},
    prometheus_vm::{HasPrometheus, PrometheusVm},
    test_env::TestEnv,
    test_env_api::{
        HasPublicApiUrl, HasTopologySnapshot, NnsCanisterWasmStrategy, NnsCustomizations,
    },
};
use ic_tests::orchestrator::utils::rw_message::install_nns_with_customizations_and_check_progress;

const API_BOUNDARY_NODE_NAME: &str = "api-boundary-node-1";

fn main() -> Result<()> {
    SystemTestGroup::new()
        .with_setup(setup)
        .execute_from_args()?;
    Ok(())
}

pub fn setup(env: TestEnv) {
    PrometheusVm::default()
        .start(&env)
        .expect("Failed to start prometheus VM");
    InternetComputer::new()
        .add_subnet(Subnet::new(SubnetType::System).add_nodes(1))
        .add_subnet(Subnet::new(SubnetType::Application).add_nodes(1))
        .with_unassigned_nodes(1)
        .setup_and_start(&env)
        .expect("Failed to setup IC under test");
    install_nns_with_customizations_and_check_progress(
        env.topology_snapshot(),
        NnsCanisterWasmStrategy::TakeBuiltFromSources,
        NnsCustomizations::default(),
    );
    // Deploy a boundary node with a boundary-api-guestos image.
    ApiBoundaryNode::new(String::from(API_BOUNDARY_NODE_NAME))
        .allocate_vm(&env)
        .expect("Allocation of ApiBoundaryNode failed.")
        .for_ic(&env, "")
        .use_real_certs_and_dns()
        .start(&env)
        .expect("failed to setup ApiBoundaryNode VM");
    let api_boundary_node = env
        .get_deployed_api_boundary_node(API_BOUNDARY_NODE_NAME)
        .unwrap()
        .get_snapshot()
        .unwrap();
    env.sync_prometheus_config_with_topology();
    // Await for API boundary node to report healthy.
    api_boundary_node
        .await_status_is_healthy()
        .expect("Boundary node did not come up healthy.");
}
