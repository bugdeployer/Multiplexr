import 'dart:convert';

import 'plugin_platform.dart';

/// Every result is validated by the host even if the script skips SDK helpers.
class ContributionValidation {
  static Never invalid() => throw const PluginDenied('invalid_response');
  static Map<String, dynamic> object(
    Object? value,
    Set<String> required, [
    Set<String> optional = const {},
  ]) {
    if (value is! Map ||
        required.any((k) => !value.containsKey(k)) ||
        value.keys.any(
          (k) => k is! String || !{...required, ...optional}.contains(k),
        )) {
      invalid();
    }
    return Map<String, dynamic>.from(value);
  }

  static String text(Object? value, [int maximum = 4096]) {
    if (value is! String || value.trim().isEmpty || value.length > maximum) {
      invalid();
    }
    return value;
  }

  static List<dynamic> list(Object? value, [int maximum = 100]) {
    if (value is! List || value.length > maximum) {
      invalid();
    }
    return value;
  }

  static void owned(Object? value, String owner) {
    if (!text(value, 200).startsWith('$owner:')) {
      invalid();
    }
  }

  static void position(Object? value) {
    if (value is! Map) {
      invalid();
    }
    final kind = value['kind'];
    if (kind == 'time') {
      final p = object(value, {'kind', 'milliseconds'});
      if (p['milliseconds'] is! int || (p['milliseconds'] as int) < 0) {
        invalid();
      }
    } else if (kind == 'text') {
      final p = object(value, {'kind', 'section', 'offset'});
      text(p['section']);
      if (p['offset'] is! int || (p['offset'] as int) < 0) {
        invalid();
      }
    } else {
      final p = object(value, {'kind', 'page', 'index', 'offset'});
      text(p['page']);
      if (kind != 'page' ||
          p['index'] is! int ||
          (p['index'] as int) < 0 ||
          p['offset'] is! num ||
          !(p['offset'] as num).isFinite ||
          (p['offset'] as num) < 0 ||
          (p['offset'] as num) > 1) {
        invalid();
      }
    }
  }

  static void node(Object? value, String owner, [int depth = 0]) {
    if (depth > 8 || value is! Map) {
      invalid();
    }
    switch (value['kind']) {
      case 'text':
        final n = object(value, {'kind', 'text'});
        if (n['text'] is! String || (n['text'] as String).length > 4096) {
          invalid();
        }
      case 'action':
        final n = object(value, {'kind', 'label', 'action'});
        text(n['label'], 200);
        owned(n['action'], owner);
      case 'group':
        final n = object(value, {'kind', 'children'});
        for (final child in list(n['children'], 32)) {
          node(child, owner, depth + 1);
        }
      default:
        invalid();
    }
  }

  static void metadataFields(Object? value) {
    final fields = object(value, {}, {
      'description',
      'language',
      'identifier',
      'publisher',
      'publicationDate',
      'series',
      'volume',
      'issue',
      'year',
      'genres',
      'director',
      'narrator',
      'artist',
      'album',
    });
    for (final entry in fields.entries) {
      if (entry.key == 'year') {
        if (entry.value is! int ||
            (entry.value as int) < 0 ||
            (entry.value as int) > 9999) {
          invalid();
        }
      } else if (entry.key == 'genres') {
        for (final genre in list(entry.value, 100)) {
          text(genre, 100);
        }
      } else {
        text(entry.value, entry.key == 'description' ? 8192 : 512);
      }
    }
  }

  static Object? result(String family, Object? value, String owner) {
    if (utf8.encode(jsonEncode(value)).length > 65536) {
      invalid();
    }
    if (family.startsWith('ui.')) {
      node(value, owner);
      return value;
    }
    if ({
      'metadata.provider',
      'artwork.provider',
      'source.provider',
    }.contains(family)) {
      final page = object(value, {'items', 'nextCursor'});
      final cursor = page['nextCursor'];
      if (cursor != null) {
        text(cursor, 256);
      }
      for (final raw in list(page['items'])) {
        if (family == 'metadata.provider') {
          final item = object(
            raw,
            {'id', 'title'},
            {'authors', 'artwork', 'fields'},
          );
          if (item['fields'] != null) {
            metadataFields(item['fields']);
          }
          owned(item['id'], owner);
          text(item['title'], 512);
          if (item['authors'] != null) {
            for (final author in list(item['authors'], 32)) {
              text(author);
            }
          }
          if (item['artwork'] != null) {
            owned(item['artwork'], owner);
          }
        } else if (family == 'artwork.provider') {
          final item = object(
            raw,
            {'id', 'role', 'attribution'},
            {'content', 'url'},
          );
          if (item['content'] != null) {
            final content = text(item['content'], 32768);
            if (!content.startsWith('data:image/png;base64,') ||
                item['url'] != null) {
              invalid();
            }
            try {
              base64Decode(content.substring(content.indexOf(',') + 1));
            } catch (_) {
              invalid();
            }
          }
          if (item['url'] != null) {
            final url = Uri.tryParse(text(item['url'], 4096));
            if (url == null ||
                url.scheme != 'https' ||
                url.host.isEmpty ||
                url.userInfo.isNotEmpty ||
                url.hasFragment ||
                item['content'] != null) {
              invalid();
            }
          }

          owned(item['id'], owner);
          text(item['attribution'], 1000);
          if (!{
            'cover',
            'poster',
            'backdrop',
            'thumbnail',
          }.contains(item['role'])) {
            invalid();
          }
        } else {
          final item = object(raw, {'id', 'name', 'mime'});
          owned(item['id'], owner);
          text(item['name'], 512);
          text(item['mime'], 100);
        }
      }
    } else if ({'library.tool', 'import.handler'}.contains(family)) {
      final output = object(value, {'proposals'});
      for (final raw in list(output['proposals'])) {
        final proposal = object(raw, {'title', 'expectedRevision', 'changes'});
        text(proposal['title']);
        text(proposal['expectedRevision']);
        final changes = object(proposal['changes'], {}, {
          'title',
          'authors',
          'description',
        });
        if (changes.isEmpty) {
          invalid();
        }
        for (final entry in changes.entries) {
          if (entry.key == 'authors') {
            for (final author in list(entry.value, 32)) {
              text(author);
            }
          } else if (entry.value is! String ||
              (entry.value as String).length >
                  (entry.key == 'description' ? 8192 : 512)) {
            invalid();
          }
        }
      }
    } else if (family == 'export.handler') {
      final output = object(value, {'name', 'mime', 'text'});
      final name = text(output['name'], 200);
      text(output['mime'], 100);
      if (name.contains(RegExp(r'[\\/\x00-\x1f]')) ||
          output['text'] is! String ||
          (output['text'] as String).length > 32768) {
        invalid();
      }
    } else if (family == 'event.handler') {
      final output = object(value, {'acknowledged'});
      if (output['acknowledged'] is! bool) {
        invalid();
      }
    } else if (family == 'session.hook') {
      final output = object(value, {'commands'});
      for (final raw in list(output['commands'], 8)) {
        if (raw is! Map) {
          invalid();
        }
        if (raw['kind'] == 'seek') {
          final command = object(raw, {'kind', 'position'});
          position(command['position']);
        } else {
          final command = object(raw, {'kind'});
          if (!{'pause', 'resume'}.contains(command['kind'])) {
            invalid();
          }
        }
      }
    } else {
      throw const PluginDenied('unsupported_capability');
    }
    return value;
  }
}
