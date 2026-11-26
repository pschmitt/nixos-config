job_dir="$RWORKER_JOBS_DIR/circus-agent"
if [[ ! -f "$job_dir/started" ]]
then
  bash "$RWORKER_JOBS_SCRIPT" register circus-agent --log /var/log/rworker-circus/agent.log
fi
