Este documento tiene como fin dar instrucciones después de bootear por primera vez la Radxa Rock 5C. **No es una documentación como tal, más bien es como una bitácora de lo que me funcionó.**

## Inicio de Radxa ROCK 5C

### Actualizar paqueteria
sudo apt-get update
sudo apt-get upgrade

### Dependencias C y build tools
sudo apt-get update && sudo apt-get install -y cmake build-essential libusb-1.0-0-dev libjpeg-dev

### Dependencias completas RTSP, gstreamer
sudo apt-get update && sudo apt-get install -y libgstreamer1.0-0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-tools gstreamer1.0-x gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-qt5 gstreamer1.0-pulseaudio libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev gstreamer1.0-rtsp libgstrtspserver-1.0-0 libgstrtspserver-1.0-dev gir1.2-gst-rtsp-server-1.0 gstreamer1.0-nice

### Dependencias de codecs por hardware
sudo add-apt-repository -y ppa:liujianfeng1994/rockchip-multimedia
sudo sed -i 's/resolute/noble/g' /etc/apt/sources.list.d/liujianfeng1994-ubuntu-rockchip-multimedia-resolute.sources
sudo apt-get update
sudo apt-get install -y rockchip-multimedia-config gstreamer1.0-rockchip

### Comprobar que los codecs ya estan
gst-inspect-1.0 | grep mpp

### Instalar rustdesk

wget https://github.com/rustdesk/rustdesk/releases/download/1.5.3/rustdesk-1.5.3-aarch64.deb
sudo apt install ./rustdesk-1.5.3-aarch64.deb

### Instalacion ricoh drivers

git clone https://github.com/ricohapi/libuvc-theta.git
sudo apt install libjpeg-dev
cd libuvc-theta
cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 ..
make
sudo make install

echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/libuvc.conf
sudo ldconfig

cd ../..
git clone https://github.com/ricohapi/libuvc-theta-sample.git
cd libuvc-theta-sample/gst
make
