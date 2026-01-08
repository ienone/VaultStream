import 'package:dio/dio.dart'; // 引入Dio库，用于HTTP请求
import 'package:riverpod_annotation/riverpod_annotation.dart'; // 引入riverpod_annotation库，用于Riverpod状态管理的注解支持

part 'api_client.g.dart'; // 生成的代码文件，源于Riverpod的代码生成

@riverpod
Dio apiClient(Ref ref) {
  // 创建并配置一个Dio客户端实例dio
  final dio = Dio(
    //配置基本选项
    BaseOptions(
      baseUrl: 'http://localhost:8000/api/v1', // 添加 API 版本前缀
      connectTimeout: const Duration(seconds: 10), // 连接超时时间
      receiveTimeout: const Duration(seconds: 10), // 接收数据超时时间
      headers: {
        'X-API-Token': '114514', // 注入 API Token 进行鉴权
      },
    ),
  );

  // 添加日志拦截器，用于打印请求和响应的详细信息，方便调试
  dio.interceptors.add(LogInterceptor(responseBody: true, requestBody: true));

  return dio;
}
