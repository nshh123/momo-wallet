import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// From your Cloudinary dashboard (Session 8, Step 4).
const _cloudName = 'YOUR_CLOUD_NAME';
const _uploadPreset = 'YOUR_UPLOAD_PRESET';

class PhotoRepository {
  /// Sends the photo to Cloudinary and returns its public secure link.
  /// Includes graceful fallback if placeholder credentials are used.
  Future<String> upload(File photo) async {
    if (_cloudName == 'YOUR_CLOUD_NAME' || _uploadPreset == 'YOUR_UPLOAD_PRESET') {
      // Demo / simulated receipt link for offline / mock testing
      return 'https://res.cloudinary.com/demo/image/upload/sample.jpg';
    }

    final url = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = _uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', photo.path));

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      throw Exception('Photo upload failed (${response.statusCode}): $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['secure_url'] as String;
  }
}
