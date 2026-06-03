import 'package:dio/dio.dart';
import 'api_client.dart';

class KnowledgeApi {
  final Dio _dio = ApiClient().dio;

  // Departments
  Future<List<Map<String, dynamic>>> getDepartments() async {
    final resp = await _dio.get('/knowledge/departments');
    return List<Map<String, dynamic>>.from(resp.data['items']);
  }

  // Categories
  Future<List<Map<String, dynamic>>> getCategories(String deptId) async {
    final resp = await _dio.get('/knowledge/$deptId/categories');
    return List<Map<String, dynamic>>.from(resp.data['items']);
  }

  Future<Map<String, dynamic>> createCategory(String deptId, {
    required String name,
    String? parentId,
    String description = '',
    String icon = 'folder',
    int sortOrder = 0,
  }) async {
    final resp = await _dio.post('/knowledge/$deptId/categories', data: {
      'name': name,
      'parent_id': parentId,
      'description': description,
      'icon': icon,
      'sort_order': sortOrder,
    });
    return resp.data;
  }

  Future<Map<String, dynamic>> updateCategory(String deptId, String catId, {
    String? name,
    String? description,
    String? icon,
    int? sortOrder,
    String? parentId,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (description != null) data['description'] = description;
    if (icon != null) data['icon'] = icon;
    if (sortOrder != null) data['sort_order'] = sortOrder;
    if (parentId != null) data['parent_id'] = parentId;
    final resp = await _dio.put('/knowledge/$deptId/categories/$catId', data: data);
    return resp.data;
  }

  Future<void> deleteCategory(String deptId, String catId) async {
    await _dio.delete('/knowledge/$deptId/categories/$catId');
  }

  // Documents
  Future<Map<String, dynamic>> getDocuments(String deptId, {
    String? categoryId,
    String search = '',
    String tags = '',
    int limit = 30,
    int offset = 0,
    bool includeArchived = false,
  }) async {
    final params = <String, dynamic>{
      'limit': limit,
      'offset': offset,
      'include_archived': includeArchived,
    };
    if (categoryId != null && categoryId.isNotEmpty) params['category_id'] = categoryId;
    if (search.isNotEmpty) params['search'] = search;
    if (tags.isNotEmpty) params['tags'] = tags;
    final resp = await _dio.get('/knowledge/$deptId/documents', queryParameters: params);
    return resp.data;
  }

  Future<Map<String, dynamic>> createDocument(String deptId, {
    required String title,
    String content = '',
    List<String> categoryIds = const [],
    List<String> tags = const [],
  }) async {
    final resp = await _dio.post('/knowledge/$deptId/documents', data: {
      'title': title,
      'content': content,
      'category_ids': categoryIds,
      'tags': tags,
    });
    return resp.data;
  }

  Future<Map<String, dynamic>> uploadDocument(String deptId, {
    required List<int> bytes,
    required String fileName,
    String categoryIds = '',
    String tags = '',
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
      'category_ids': categoryIds,
      'tags': tags,
    });
    final resp = await _dio.post('/knowledge/$deptId/documents/upload', data: formData);
    return resp.data;
  }

  Future<Map<String, dynamic>> getDocument(String deptId, String docId) async {
    final resp = await _dio.get('/knowledge/$deptId/documents/$docId');
    return resp.data;
  }

  Future<Map<String, dynamic>> getDocumentFileUrl(String deptId, String docId) async {
    final resp = await _dio.get('/knowledge/$deptId/documents/$docId/file-url');
    return resp.data;
  }

  Future<void> deleteDocument(String deptId, String docId) async {
    await _dio.delete('/knowledge/$deptId/documents/$docId');
  }

  Future<void> archiveDocument(String deptId, String docId, bool archive) async {
    await _dio.patch('/knowledge/$deptId/documents/$docId/archive', queryParameters: {'archive': archive});
  }

  Future<Map<String, dynamic>> updateDocument(String deptId, String docId, {
    String? title,
    String? content,
    List<String>? tags,
  }) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (content != null) data['content'] = content;
    if (tags != null) data['tags'] = tags;
    final resp = await _dio.put('/knowledge/$deptId/documents/$docId', data: data);
    return resp.data;
  }

  Future<void> updateDocumentCategories(String deptId, String docId, List<String> categoryIds) async {
    await _dio.put('/knowledge/$deptId/documents/$docId/categories', data: {
      'category_ids': categoryIds,
    });
  }

  Future<Map<String, dynamic>> moveDocument(String deptId, String docId, String targetCategoryId) async {
    final resp = await _dio.put('/knowledge/$deptId/documents/$docId/move', data: {
      'target_category_id': targetCategoryId,
    });
    return resp.data;
  }

  Future<Map<String, dynamic>> moveCategory(String deptId, String catId, {String? targetParentId}) async {
    final resp = await _dio.put('/knowledge/$deptId/categories/$catId/move', data: {
      'target_parent_id': targetParentId,
    });
    return resp.data;
  }

  // Chat
  Future<Map<String, dynamic>> chat(String deptId, {
    required String question,
    int topK = 5,
    List<Map<String, dynamic>> history = const [],
  }) async {
    final resp = await _dio.post('/knowledge/$deptId/chat', data: {
      'question': question,
      'top_k': topK,
      'history': history,
    });
    return resp.data;
  }

  Future<List<Map<String, dynamic>>> getChatHistory(String deptId, {int limit = 50}) async {
    final resp = await _dio.get('/knowledge/$deptId/chat/history', queryParameters: {'limit': limit});
    return List<Map<String, dynamic>>.from(resp.data['items']);
  }
}
