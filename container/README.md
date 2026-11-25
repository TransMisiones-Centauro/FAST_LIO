# Running FAST-LIO in a container (Podman or Docker)

These instructions build and run a ROS 2 Jazzy container image with FAST-LIO and the Livox drivers.
The `main` branch of this repository is for ROS 1. The image is built from
[Ericsii/FAST_LIO_ROS2](https://github.com/Ericsii/FAST_LIO_ROS2) (branch `ros2`), the ROS 2 port that the `ROS2`
branch of this repository is based on.

The instructions work with both [Podman](https://podman.io/) and [Docker](https://docs.docker.com/), because the two tools
take the same command-line syntax for everything used here. Pick one and set a shell variable so the commands
below can be copied as they are:

```bash
ENGINE=podman   # or: ENGINE=docker
```

Differences between the two:

| | Podman | Docker |
|---|---|---|
| Daemon | None. Containers are child processes of the user | Run by the `dockerd` daemon, usually as root |
| Run as normal user | Yes (rootless by default) | Only if the user is in the `docker` group, or with `sudo` |
| X11 access (`xhost`) | `xhost +local:$USER` | `xhost +local:root` (the container runs as root) |
| Image names | Use fully qualified names (`docker.io/...`, `ghcr.io/...`) | `docker.io/` can be left out |

Podman can also replace Docker transparently: `alias docker=podman`, or install the `podman-docker` package.

## Get the image

### Option 1: download the published image

The image is built, tested and published automatically (see [Automatic builds](#automatic-builds)):

```bash
$ENGINE pull ghcr.io/transmisiones-centauro/fast_lio:latest
```

### Option 2: build it with the Dockerfile

From the root of this repository:

```bash
$ENGINE build -f container/Dockerfile -t ghcr.io/transmisiones-centauro/fast_lio:latest .
```

The [Dockerfile](Dockerfile) starts from `docker.io/osrf/ros:jazzy-desktop-full`, clones the Livox SDK, the Livox driver, the Livox/PointCloud2 converter and the `ros2` branch of
[Ericsii/FAST_LIO_ROS2](https://github.com/Ericsii/FAST_LIO_ROS2), and builds them in `/ros2_ws`. To build another
repository or branch of FAST-LIO, add `--build-arg FAST_LIO_REPO=<url>` or `--build-arg FAST_LIO_BRANCH=<branch>`.

Check that the image works by running the functional test (see [Automatic builds](#automatic-builds)):

```bash
$ENGINE run --rm ghcr.io/transmisiones-centauro/fast_lio:latest bash /test/run_test.sh
```

### Option 3: build it by hand

Start a container from the official ROS 2 Jazzy image:

```bash
$ENGINE pull docker.io/osrf/ros:jazzy-desktop-full
$ENGINE run -it --name fast_lio docker.io/osrf/ros:jazzy-desktop-full
```

Inside the container, build the Livox SDK, then clone the Livox driver, the converter between Livox and
`PointCloud2` messages, and FAST-LIO, and build them all:

```bash
apt update && apt -y upgrade

# Livox SDK 2
cd /
git clone https://github.com/qza36/Livox-SDK2.git
cd Livox-SDK2/
mkdir build && cd build
cmake .. && make -j && make install

# Livox ROS 2 driver, Livox <-> PointCloud2 converter, and FAST-LIO
mkdir -p /ros2_ws/src
cd /ros2_ws/src/
git clone -b feature/use-standard-unit https://github.com/Ericsii/livox_ros_driver2.git ws_livox/src/livox_ros_driver2
git clone https://github.com/ecervera/livox_to_pointcloud2.git ws_livox/src/livox_to_pointcloud2
git clone --recursive -b ros2 https://github.com/Ericsii/FAST_LIO_ROS2.git
cd ..
colcon build
exit
```

`--recursive` is needed to fetch the `ikd-Tree` submodule of FAST-LIO.

Save the container as a new image and, optionally, publish it to the GitHub Container Registry.
To push, you must log in first with a GitHub personal access token that has the `write:packages` scope:

```bash
$ENGINE commit fast_lio ghcr.io/transmisiones-centauro/fast_lio:latest
$ENGINE rm fast_lio

$ENGINE login ghcr.io
$ENGINE push ghcr.io/transmisiones-centauro/fast_lio:latest
```

Replace `ghcr.io/transmisiones-centauro/fast_lio` with your own registry and namespace if needed.

## Run the container

Allow the container to open windows on the host X server (needed for RViz):

```bash
xhost +local:$USER   # Podman (rootless)
xhost +local:root    # Docker
```

Then start the container:

```bash
$ENGINE run -it --rm --name fast_lio \
    --env="DISPLAY=$DISPLAY" \
    --env="QT_X11_NO_MITSHM=1" \
    --volume="/tmp/.X11-unix:/tmp/.X11-unix:rw" \
    --device /dev/dri \
    ghcr.io/transmisiones-centauro/fast_lio:latest
```

Useful additional options:

- `--net=host --ipc=host`: share the host network and IPC, so that ROS 2 nodes inside the container can discover
  nodes on the host or on the robot. A Livox LiDAR connected over Ethernet also needs the host network.
- `--volume="$HOME/rosbags:/rosbags:rw"`: make a host directory with rosbags available inside the container.
- `--volume="$HOME/maps:/ros2_ws/src/FAST_LIO_ROS2/PCD:rw"`: keep the maps saved by FAST-LIO after the container
  is removed.
- `--security-opt label=disable`: on SELinux hosts (Fedora, RHEL), allows the container to access the X11 socket.

## Use FAST-LIO

FAST-LIO needs a LiDAR topic and a `sensor_msgs/Imu` topic. The LiDAR and the IMU must be time-synchronized.

### Parameters

The parameters are in YAML files in `/ros2_ws/src/FAST_LIO_ROS2/config/`, one per sensor (`mid360.yaml`,
`avia.yaml`, `horizon.yaml`, `velodyne.yaml`, `ouster64.yaml`). The package is built without `--symlink-install`,
so after editing a file, either run `colcon build` again or pass the source folder at launch with
`config_path:=/ros2_ws/src/FAST_LIO_ROS2/config`.

**Topics and LiDAR type**

```yaml
        common:
            lid_topic:  "/livox/lidar"
            imu_topic:  "/livox/imu"
        preprocess:
            lidar_type: 1
```

`lidar_type` selects the message type and how the time of each point is obtained, which FAST-LIO uses to correct
the motion distortion inside each scan:

| `lidar_type` | Input message | Time of each point |
|---|---|---|
| 1 (Livox) | `livox_ros_driver2/CustomMsg` | `offset_time` field of each point |
| 2 (Velodyne) | `sensor_msgs/PointCloud2` | `time` field, or estimated from the rotation angle |
| 3 (Ouster) | `sensor_msgs/PointCloud2` | `t` field |
| 4 (Livox MID-360) | `sensor_msgs/PointCloud2` with Livox fields | Estimated from the rotation angle |
| Any other value | `sensor_msgs/PointCloud2` | None (no motion correction) |

If the robot publishes the Livox point cloud as `PointCloud2`, there are two options:

- Set `lidar_type: 4` and remap the topics when playing the rosbag (this is the configuration of the published image):
  ```bash
  ros2 bag play --clock /rosbags/<rosbag> \
      --remap /utlidar/imu_livox_mid360:=/livox/imu /utlidar/cloud_livox_mid360:=/livox/lidar
  ```
- Keep `lidar_type: 1` and convert the point cloud to `CustomMsg`, published on `/livox/lidar`:
  ```bash
  ros2 launch livox_to_pointcloud2 pointcloud2_to_livox_launch.py pcloud_topic:=/utlidar/cloud_livox_mid360
  ```

**IMU and LiDAR position**

```yaml
        mapping:
            extrinsic_est_en:  true
            extrinsic_T: [ -0.011, -0.02329, 0.04412 ]
            extrinsic_R: [ 1., 0., 0.,
                           0., 1., 0.,
                           0., 0., 1.]
```

- `extrinsic_T` and `extrinsic_R` are the position (in meters) and rotation (3×3 matrix, row by row) of the
  **LiDAR in the IMU frame**. The values above are for the integrated IMU of the Livox MID-360.
  Note that this is the opposite convention from DLIO, which gives the IMU position relative to the base.
- `extrinsic_est_en: true` refines the extrinsics online. The FAST-LIO authors recommend setting it to `false`
  when the extrinsics are known.

**Frames**

The frame names are fixed in the code: FAST-LIO publishes the odometry, the path and the map in the `camera_init`
frame, and the TF `camera_init` → `body`, where `body` is the IMU. To connect them with the rest of the robot's
TF tree, publish a static transform between `body` and the robot base, or between your map frame and `camera_init`.

**Saving the map**

With `pcd_save_en: true` (the default in `mid360.yaml`), all scans are accumulated and saved to
`/ros2_ws/src/FAST_LIO_ROS2/PCD/scans.pcd` when FAST-LIO stops.

### Run

Inside the container, source the workspace and launch FAST-LIO with the configuration file for your sensor:

```bash
source /ros2_ws/install/setup.bash
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml
```

With rosbags, add `use_sim_time:=true` to the launch command and play the bag with `--clock`, from a second shell
in the same container (open it from another terminal on the host):

```bash
$ENGINE exec -it fast_lio bash
# inside the container:
source /ros2_ws/install/setup.bash
ros2 bag play --clock /rosbags/<rosbag>
```

## Automatic builds

The workflow [`.github/workflows/container.yml`](../.github/workflows/container.yml) runs on every push to this
repository, and can also be started by hand from the *Actions* tab. It:

1. Builds the image with `container/Dockerfile`.
2. Runs the functional test, [`container/test/run_test.sh`](test/run_test.sh). The test starts
   FAST-LIO with its Velodyne configuration (`config/velodyne.yaml`, `lidar_type: 2`), and [publishes synthetic data](test/synthetic_sensors.py) for 25 seconds: a static sensor in
   a box-shaped room, with an IMU at 200 Hz and a point cloud at 10 Hz. It passes if at least 50 odometry messages
   are published and the estimated position stays within 0.5 m of the origin.
3. Publishes the image to `ghcr.io/transmisiones-centauro/fast_lio`, only if the test passed, with these tags:
   - the branch name (for example `main`), always pointing to the latest build of that branch;
   - `sha-<commit>`, one per build;
   - `latest`, only for builds of the default branch.

For the workflow to publish, the `fast_lio` package must give this repository write access: in the package
settings, under *Manage Actions access*, add this repository with the *Write* role.

The image is built from the `ros2` branch of `Ericsii/FAST_LIO_ROS2`, not from this repository (whose `main` branch is for ROS 1). A push to this repository rebuilds and retests the image, but changes in `Ericsii/FAST_LIO_ROS2` are only picked up on the next push or manual run.
