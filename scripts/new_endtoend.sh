#!/bin/bash
./cleanup.sh --app velociraptor
./"apps/velociraptor.sh"
#./libs/install-pre-requisites.sh
./new_deploy_services.sh
./new_enable_all.sh
./test_agent.sh
./new_pipline.sh
./data_view_haybo.sh
./enable_logs.sh
./winlogbeat_piplines.sh
./Lowercase_Normalization_Pipeline.sh
./fleet_final_pipeline.sh
./update_db_password.sh
./remove_interval_file.sh
./copy_agent_scripts.sh
