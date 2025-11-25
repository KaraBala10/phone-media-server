# 📱 Phone Media Server

![Flutter](https://img.shields.io/badge/Flutter-3.0+-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Android-green.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

**Transform your Android phone into a beautiful, modern media server via WiFi Hotspot!**

Share photos and videos instantly with any device connected to your phone's hotspot. No cables, no internet connection needed - just pure local network magic! ✨

## 🎯 Features

### Core Features
- 🌐 **WiFi Hotspot Server** - Share media over your phone's hotspot
- 📸 **Photo & Video Support** - Serve all types of media files
- 🗺️ **Custom Routes** - Create custom URLs for specific media files
- 🎨 **Modern UI** - Beautiful Material Design 3 interface
- 📊 **Real-time Stats** - Track images, videos, and total files
- 🔄 **Auto IP Detection** - Automatically finds your wlan0 IP address

### Smart Features
- ✅ **Automatic Hotspot Detection** - Checks if hotspot is enabled before starting
- 🛑 **Auto-Stop on Hotspot Disable** - Server stops when hotspot is turned off
- ⚙️ **Quick Settings Access** - Opens hotspot settings with one tap
- 🔍 **Hotspot Monitoring** - Continuously monitors hotspot status
- 💾 **Persistent Routes** - Routes are saved and restored automatically

### Web Interface
- 🎬 **Beautiful Gallery View** - Gradient design with animated elements
- 🖼️ **Route Cards** - Color-coded cards for images (blue) and videos (purple)
- 📱 **Responsive Design** - Works perfectly on all screen sizes
- 🚀 **No Cache Issues** - Smart cache control for instant updates

## 📸 Screenshots

### Mobile App
- **Home Screen**: Server control with status, URL display, and route management
- **Routes Management**: Add, view, and delete custom routes
- **Auto Hotspot Check**: Smart dialogs for hotspot status

### Web Interface
- **Modern Gallery**: Beautiful gradient design with route cards
- **Route Cards**: Large, tappable cards with media preview
- **Empty State**: Friendly messages when no routes exist

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.0 or higher
- Android device (Android 6.0+)
- Android Studio or VS Code with Flutter extensions

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/hotspot-media-server.git
   cd hotspot-media-server
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

## 📖 How to Use

### Setup
1. **Enable WiFi Hotspot** on your Android phone
2. **Launch the app** and grant storage permissions
3. **Tap "Start Server"** - The app will auto-detect if hotspot is on
4. **Copy the server URL** displayed (e.g., `http://192.168.43.1:8080`)

### Adding Routes
1. Tap **"Manage Routes"** in the app
2. Tap **"Add New Route"**
3. Enter a **route name** (e.g., `photo1`, `vacation-video`)
4. **Select a media file** from your phone
5. The route is now accessible at `http://YOUR_IP:8080/route-name`

### Accessing from Other Devices
1. **Connect the other device** to your phone's hotspot
2. **Open a browser** and enter the server URL
3. You'll see **beautiful cards** for each route
4. **Tap any card** to view the media in full screen

## 🛠️ Tech Stack

- **Flutter** - Cross-platform mobile framework
- **Shelf** - Dart HTTP server
- **Photo Manager** - Access device media
- **File Picker** - Select files from storage
- **Shared Preferences** - Persistent storage
- **Android Intent Plus** - Open system settings
- **Permission Handler** - Manage app permissions

## 📁 Project Structure

```
lib/
├── main.dart              # Main app entry & UI
├── server.dart            # HTTP server & web interface
├── route_manager.dart     # Custom routes management
└── media_service.dart     # Media file access & handling
```

## 🎨 Design Features

### App Theme
- Primary Color: `#6C63FF` (Purple)
- Secondary Color: `#4CAF50` (Green)
- Modern gradients and shadows
- Smooth animations

### Web Interface
- Gradient header with floating animation
- Color-coded media badges
- Material Design cards
- Loading states with spinners
- Beautiful empty states

## ⚙️ Configuration

### Default Settings
- **Port**: 8080
- **IP Detection**: Automatic (wlan0)
- **Hotspot Check Interval**: 3 seconds
- **Cache Control**: Disabled for instant updates

### Customization
You can modify these in the code:
- Port number in `main.dart` (`_port` variable)
- Check interval in `main.dart` (`Timer.periodic` duration)
- Colors in `main.dart` (theme configuration)

## 🔒 Permissions Required

- **Storage** - Read photos and videos
- **Network** - Create HTTP server
- **WiFi State** - Check hotspot status

## 🐛 Troubleshooting

### Server won't start
- Ensure WiFi hotspot is enabled
- Check that port 8080 is not in use
- Grant all required permissions

### Can't access from other devices
- Verify both devices are on the same hotspot
- Check firewall settings
- Try the exact IP shown in the app

### Old content showing in browser
- Clear browser cache (Ctrl+Shift+R)
- Use Incognito/Private mode
- The app now includes strong cache-busting headers

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the project
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- Shelf package for the HTTP server
- All the package maintainers

## 📧 Contact

Project Link: [https://github.com/KaraBala10/hotspot-media-server](https://github.com/YOUR_USERNAME/hotspot-media-server)

---

**Made with ❤️ and Flutter**

⭐ **Star this repo if you find it useful!**
