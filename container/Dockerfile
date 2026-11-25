# ROS 2 Jazzy image with FAST-LIO and the Livox drivers.
#
# Build from the root of the repository:
#   podman build -f container/Dockerfile -t ghcr.io/transmisiones-centauro/fast_lio:latest .
#   docker build -f container/Dockerfile -t ghcr.io/transmisiones-centauro/fast_lio:latest .

FROM docker.io/osrf/ros:jazzy-desktop-full

# The main branch of this repository is for ROS 1. The image is built from the ROS 2 port.
ARG FAST_LIO_REPO=https://github.com/Ericsii/FAST_LIO_ROS2.git
ARG FAST_LIO_BRANCH=ros2

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

# Livox SDK 2
WORKDIR /
RUN git clone --depth 1 https://github.com/qza36/Livox-SDK2.git \
    && cmake -S Livox-SDK2 -B Livox-SDK2/build \
    && cmake --build Livox-SDK2/build -j"$(nproc)" \
    && cmake --install Livox-SDK2/build

# Livox ROS 2 driver, Livox <-> PointCloud2 converter, and FAST-LIO
WORKDIR /ros2_ws/src
RUN git clone --depth 1 -b feature/use-standard-unit https://github.com/Ericsii/livox_ros_driver2.git ws_livox/src/livox_ros_driver2 \
    && git clone --depth 1 https://github.com/ecervera/livox_to_pointcloud2.git ws_livox/src/livox_to_pointcloud2 \
    && git clone --depth 1 --recursive --shallow-submodules -b "${FAST_LIO_BRANCH}" "${FAST_LIO_REPO}" FAST_LIO_ROS2

WORKDIR /ros2_ws
RUN . /opt/ros/${ROS_DISTRO}/setup.sh \
    && colcon build \
    && echo "source /ros2_ws/install/setup.bash" >> /root/.bashrc

# Functional test, used by the GitHub workflow (see container/test/).
COPY container/test /test

CMD ["bash"]
