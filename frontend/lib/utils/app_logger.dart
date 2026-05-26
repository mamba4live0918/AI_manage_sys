import 'app_logger_impl.dart'
    if (dart.library.html) 'app_logger_web.dart';

void appLog(String msg) => logImpl(msg);
