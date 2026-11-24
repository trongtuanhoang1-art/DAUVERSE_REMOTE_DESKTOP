enum DauverseScreenId {
  dashboard,
  myDevices,
  remoteSession,
  miniControl,
  fileTransfer,
  clipboardSettings,
  aiLiveStatus,
  notificationCenter,
  hardwareMonitor,
  smartPower,
  securityCenter,
  sessionHistory,
  networkDiagnostics,
  updateCenter,
  settings,
  about,
}

class DauverseI18n {
  final bool isVi;
  const DauverseI18n(this.isVi);

  String screenTitle(DauverseScreenId id) {
    switch (id) {
      case DauverseScreenId.dashboard:
        return isVi ? 'Bảng điều hành (Dashboard)' : 'Executive Dashboard';
      case DauverseScreenId.myDevices:
        return isVi ? 'Thiết bị của tôi' : 'My Devices';
      case DauverseScreenId.remoteSession:
        return isVi ? 'Phiên điều khiển từ xa' : 'Remote Session';
      case DauverseScreenId.miniControl:
        return isVi ? 'Mini Control (Cửa sổ nổi)' : 'Mini Control';
      case DauverseScreenId.fileTransfer:
        return isVi ? 'Trung tâm truyền dữ liệu' : 'File Transfer Center';
      case DauverseScreenId.clipboardSettings:
        return isVi ? 'Smart Clipboard' : 'Clipboard Settings';
      case DauverseScreenId.aiLiveStatus:
        return isVi ? 'Trạng thái AI trực tiếp' : 'AI Live Status';
      case DauverseScreenId.notificationCenter:
        return isVi ? 'Trung tâm thông báo AI' : 'Notification Center';
      case DauverseScreenId.hardwareMonitor:
        return isVi ? 'Giám sát phần cứng' : 'Hardware Monitor';
      case DauverseScreenId.smartPower:
        return isVi ? 'Điều khiển nguồn thông minh' : 'Smart Power';
      case DauverseScreenId.securityCenter:
        return isVi ? 'Khiên bảo mật (Device Shield)' : 'Security Center';
      case DauverseScreenId.sessionHistory:
        return isVi ? 'Nhật ký phiên kết nối' : 'Session History';
      case DauverseScreenId.networkDiagnostics:
        return isVi ? 'Chẩn đoán mạng & P2P' : 'Network Diagnostics';
      case DauverseScreenId.updateCenter:
        return isVi ? 'Cập nhật & Phiên bản' : 'Update Center';
      case DauverseScreenId.settings:
        return isVi ? 'Cài đặt hệ thống' : 'Settings';
      case DauverseScreenId.about:
        return isVi ? 'Giới thiệu & Giấy phép' : 'About & Compliance';
    }
  }

  String t(String vi, String en) => isVi ? vi : en;
}
