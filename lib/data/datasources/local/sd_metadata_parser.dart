import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import '../../../domain/entities/image_tag_result.dart';
import 'png_metadata_service.dart';

class SdMetadataParser {
  static Future<ImageTagResult?> parse(String path) => compute(_readFile, path);

  static Future<ImageTagResult?> _readFile(String path) async =>
      parseBytes(await File(path).readAsBytes());

  static ImageTagResult? parseBytes(Uint8List bytes) {
    if (bytes.length < 12) return null;
    String? text;
    if (bytes[0] == 0x89 &&
        ascii.decode(bytes.sublist(1, 4), allowInvalid: true) == 'PNG') {
      text = PngMetadataService.readText(bytes)['parameters'];
    } else {
      img.ExifData? exif;
      if (bytes[0] == 0xff && bytes[1] == 0xd8) {
        exif = img.decodeJpgExif(bytes);
      } else if (latin1.decode(bytes.sublist(0, 4)) == 'RIFF' &&
          latin1.decode(bytes.sublist(8, 12)) == 'WEBP') {
        final data = ByteData.sublistView(bytes);
        for (var pos = 12; pos + 8 <= bytes.length;) {
          final length = data.getUint32(pos + 4, Endian.little);
          final start = pos + 8;
          if (length > bytes.length - start) return null;
          if (latin1.decode(bytes.sublist(pos, pos + 4)) == 'EXIF') {
            final hasPrefix = length >= 6 &&
                latin1.decode(bytes.sublist(start, start + 6)) ==
                    'Exif\x00\x00';
            exif = img.ExifData.fromInputBuffer(img.InputBuffer(
                Uint8List.sublistView(
                    bytes, start + (hasPrefix ? 6 : 0), start + length)));
            break;
          }
          pos = start + length + (length.isOdd ? 1 : 0);
        }
      }
      final value = exif?.exifIfd[0x9286] ?? exif?.imageIfd[0x9286];
      if (value != null) text = _comment(value.toData());
    }
    return text == null ? null : parseParameters(text);
  }

  static String _comment(Uint8List bytes) {
    final header = bytes.length >= 8 ? latin1.decode(bytes.sublist(0, 8)) : '';
    if (header == 'UNICODE\x00') {
      final data = ByteData.sublistView(bytes, 8);
      if (data.lengthInBytes < 2) return '';
      final marker = data.getUint16(0);
      final little = marker == 0xfffe ||
          (marker != 0xfeff && data.getUint8(1) == 0 && data.getUint8(0) != 0);
      return String.fromCharCodes([
        for (var i = marker == 0xfffe || marker == 0xfeff ? 2 : 0;
            i + 1 < data.lengthInBytes;
            i += 2)
          data.getUint16(i, little ? Endian.little : Endian.big)
      ]).replaceAll('\x00', '');
    }
    final payload = header == 'ASCII\x00\x00\x00' ? bytes.sublist(8) : bytes;
    return utf8.decode(payload, allowMalformed: true).replaceAll('\x00', '');
  }

  static ImageTagResult? parseParameters(String raw) {
    final text = raw.replaceAll('\r\n', '\n').trim();
    final blocks = RegExp(r'^Steps:\s*\d+\b', multiLine: true).allMatches(text);
    if (blocks.isEmpty) return null;
    final split = blocks.last.start;
    final prompts = text.substring(0, split).trimRight();
    final divider =
        RegExp(r'^Negative prompt:[ \t]*', multiLine: true).firstMatch(prompts);
    final positive = prompts.substring(0, divider?.start).trim();
    final negative =
        divider == null ? '' : prompts.substring(divider.end).trim();
    final params = <String, dynamic>{};
    final fields = RegExp(
        r'(?:^|,\s*)([\w][\w .+/-]*?):\s*("(?:\\.|[^"\\])*"|.*?)(?=,\s*[\w][\w .+/-]*?:|$)',
        dotAll: true);
    for (final field in fields.allMatches(text.substring(split))) {
      params[field[1]!.trim()] = field[2]!.trim();
    }
    // Preserve weighted groups, LoRA expressions, escapes and multiline prompts.
    List<TagEntry> tags(String prompt) {
      final result = <TagEntry>[];
      var start = 0, depth = 0;
      for (var i = 0; i <= prompt.length; i++) {
        final c = i == prompt.length ? '' : prompt[i];
        if (c == r'\' && i + 1 < prompt.length) {
          i++;
          continue;
        }
        if (c.isEmpty || (c == ',' && depth == 0)) {
          final tag = prompt.substring(start, i).trim();
          if (tag.isNotEmpty) result.add(TagEntry(tag: tag));
          start = i + 1;
        } else if ('([<'.contains(c)) {
          depth++;
        } else if (')]>'.contains(c) && depth > 0) {
          depth--;
        }
      }
      return result;
    }

    return ImageTagResult(
        source: TagSource.sdMetadata,
        general: tags(positive),
        negativePrompt: negative,
        negativeEntries: tags(negative),
        metadata: {...params, '完整生成信息': raw});
  }
}
