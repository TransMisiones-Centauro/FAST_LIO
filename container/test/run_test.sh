#!/bin/bash
# Functional test of the FAST-LIO image: start FAST-LIO, feed it synthetic sensor data and check its odometry.
# Run it inside the container:
#   podman run --rm ghcr.io/transmisiones-centauro/fast_lio:latest bash /test/run_test.sh

source /opt/ros/${ROS_DISTRO}/setup.bash
source /ros2_ws/install/setup.bash

echo "== Starting FAST-LIO"
ros2 launch fast_lio mapping.launch.py config_file:=velodyne.yaml rviz:=false use_sim_time:=true > /tmp/odometry.log 2>&1 &
LAUNCH_PID=$!
sleep 5

echo "== Publishing synthetic sensor data"
python3 /test/synthetic_sensors.py --imu-topic /imu/data --cloud-topic /velodyne_points --odom-topic /Odometry --time-scale 1e6
RESULT=$?

# Stop FAST-LIO. Background jobs of a non-interactive shell ignore SIGINT, so send SIGTERM,
# and kill whatever is still running after 10 seconds.
kill -TERM $LAUNCH_PID 2>/dev/null
for _ in $(seq 10); do kill -0 $LAUNCH_PID 2>/dev/null || break; sleep 1; done
pkill -KILL -P $LAUNCH_PID 2>/dev/null
kill -KILL $LAUNCH_PID 2>/dev/null

if [ $RESULT -ne 0 ]; then
    echo "== FAST-LIO output"
    tail -n 50 /tmp/odometry.log
fi
exit $RESULT
