import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_studio/audio/wav_writer.dart';
import 'package:voice_studio/models/models.dart';
import 'package:voice_studio/readers/text_formats.dart';
import 'package:voice_studio/services/backend/backend_client.dart';
import 'package:voice_studio/transcription/transcript_export.dart';

void main() {
  test('WhatsApp export is detected and formatted', () {
    const chat = '15/11/26, 10:30 - Ana: Mañana empezamos a las 7\n'
        '15/11/26, 10:31 - Luis: ¿Llevo los 20 tubos EMT?\n'
        'y también las cajas\n'
        '[15/11/26 10:32:00] Ana: Sí, por favor';
    expect(looksLikeWhatsAppChat(chat), isTrue);
    final out = formatWhatsAppChat(chat).split('\n\n');
    expect(out.length, 3);
    expect(out[0], 'Ana (15/11/26 10:30): Mañana empezamos a las 7');
    expect(out[1], 'Luis (15/11/26 10:31): ¿Llevo los 20 tubos EMT? y también las cajas');
    expect(looksLikeWhatsAppChat('Texto normal.\nOtra línea.'), isFalse);
  });

  test('tables with headers read as "Header: value"', () {
    final t = tableToText([
      ['Material', 'Cantidad', 'Unidad'],
      ['Cable THHN 12', '500', 'ft'],
      ['', '', ''],
      ['Tubo EMT 3/4"', '20', 'pz'],
    ]);
    expect(t, contains('Fila 1. Material: Cable THHN 12; Cantidad: 500; Unidad: ft.'));
    expect(t, contains('Fila 2. Material: Tubo EMT 3/4"; Cantidad: 20; Unidad: pz.'));
  });

  test('HTML main content extraction drops navigation and scripts', () {
    const html = '<html><head><title>Guía</title><script>x()</script></head><body>'
        '<nav>Menú Inicio</nav><article><h1>Instalación</h1><p>Paso uno.</p><ul><li>Tubo</li></ul></article>'
        '<footer>Copyright</footer></body></html>';
    final r = htmlToText(html);
    expect(r.title, 'Guía');
    expect(r.text, 'Instalación\n\nPaso uno.\n\n- Tubo');
  });

  test('EML parsing: multipart, quoted-printable, encoded subject, attachments', () {
    const eml = 'From: Jefe <jefe@example.com>\r\n'
        'Subject: =?UTF-8?B?T3JkZW4gZGUgdHJhYmFqbyBuwrogNQ==?=\r\n'
        'Date: Sun, 15 Nov 2026 08:00:00 +0000\r\n'
        'Content-Type: multipart/mixed; boundary="XYZ"\r\n'
        '\r\n'
        '--XYZ\r\n'
        'Content-Type: text/plain; charset=utf-8\r\n'
        'Content-Transfer-Encoding: quoted-printable\r\n'
        '\r\n'
        'Instalar el panel ma=C3=B1ana.\r\n'
        '--XYZ\r\n'
        'Content-Type: application/pdf; name="plano.pdf"\r\n'
        'Content-Disposition: attachment; filename="plano.pdf"\r\n'
        '\r\n'
        'JVBERi0=\r\n'
        '--XYZ--\r\n';
    final m = parseEml(eml);
    expect(m.subject, 'Orden de trabajo nº 5');
    expect(m.body, 'Instalar el panel mañana.');
    expect(m.attachments, ['plano.pdf']);
    expect(m.toReadableText(), contains('Adjuntos: plano.pdf.'));
  });

  test('WAV header is valid PCM16 mono 16 kHz', () {
    final h = WavWriter.header(32000);
    final b = ByteData.sublistView(h);
    expect(String.fromCharCodes(h.sublist(0, 4)), 'RIFF');
    expect(b.getUint32(4, Endian.little), 36 + 32000);
    expect(b.getUint16(22, Endian.little), 1);
    expect(b.getUint32(24, Endian.little), 16000);
    expect(b.getUint16(34, Endian.little), 16);
    expect(b.getUint32(40, Endian.little), 32000);
  });

  test('transcript export formats', () {
    final rec = Recording(id: 'r1', title: 'Reunión', durationMs: 15000);
    final segs = [
      TranscriptSegment(recordingId: 'r1', index: 0, startMs: 4000, endMs: 8000, speaker: 'S1', text: 'Mañana necesitamos comenzar la instalación.'),
      TranscriptSegment(recordingId: 'r1', index: 1, startMs: 9000, endMs: 12500, speaker: 'S2', text: '¿Ya tenemos todos los materiales?'),
    ];
    final txt = TranscriptExport.toText(rec, segs, {'S2': 'Luis'});
    expect(txt, contains('Persona 1 — 00:00:04\n"Mañana necesitamos comenzar la instalación."'));
    expect(txt, contains('Luis — 00:00:09'));
    final srt = TranscriptExport.toSrt(segs, {});
    expect(srt, startsWith('1\n00:00:04,000 --> 00:00:08,000\nPersona 1: Mañana'));
    expect(TranscriptExport.toJson(rec, segs, {}), contains('"S2": "Persona 2"'));
  });

  test('plain HTTP is only flagged for servers outside the local network', () {
    for (final ok in [
      'http://127.0.0.1:8765', 'http://localhost:8765', 'http://192.168.1.20:8765', 'http://10.0.0.5:8765',
      'http://172.20.1.2:8765', 'http://mipc.local:8765', 'https://voice.example.com', 'https://8.8.8.8',
    ]) {
      expect(isInsecureRemoteUrl(ok), isFalse, reason: ok);
    }
    for (final bad in ['http://voice.example.com', 'http://8.8.8.8:8765', 'http://172.32.0.1']) {
      expect(isInsecureRemoteUrl(bad), isTrue, reason: bad);
    }
  });

  test('speaker defaults and timestamps', () {
    expect(defaultSpeakerName('S3'), 'Persona 3');
    expect(formatTimestamp(3723000), '01:02:03');
  });
}
