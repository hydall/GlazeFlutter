import 'package:flutter/material.dart';

import '../image_gen_models.dart';
import 'rows.dart' as rows;

/// Connection-field rows for the Naistera image-gen API.
///
/// The "Learn about Naistera" link is shown as an inert InkWell because
/// the original implementation did not actually wire a URL — preserved
/// here to avoid behavior change.
List<Widget> buildNaisteraConnectionFields(
  ImageGenSettings s,
  ValueChanged<ImageGenSettings> onUpdate,
) {
  return [
    rows.ImageGenTextFieldItem(
      label: 'API Key',
      value: s.naisteraApiKey,
      obscure: true,
      hint: 'sk-...',
      onChanged: (v) => onUpdate(s.copyWith(naisteraApiKey: v)),
    ),
    InkWell(
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
        ),
        child: const Row(
          children: [
            Text('Learn about Naistera', style: TextStyle(fontSize: 13)),
            SizedBox(width: 4),
            Icon(Icons.public, size: 14, color: Colors.blue),
            SizedBox(width: 4),
            Text(
              'here',
              style: TextStyle(fontSize: 13, color: Colors.blue),
            ),
          ],
        ),
      ),
    ),
  ];
}

/// Connection-field rows for the rout.my image-gen API. The Russian
/// variant (ruRoutmy) shares the same shape and only differs in the
/// settings field it writes to, controlled by [isRu].
List<Widget> buildRoutmyConnectionFields(
  ImageGenSettings s, {
  required bool isRu,
  required ValueChanged<ImageGenSettings> onUpdate,
}) {
  return [
    rows.ImageGenTextFieldItem(
      label: isRu ? 'RU-rout.my API Key' : 'rout.my API Key',
      value: isRu ? s.ruRoutmyApiKey : s.routmyApiKey,
      obscure: true,
      hint: 'sk-...',
      onChanged: (v) => isRu
          ? onUpdate(s.copyWith(ruRoutmyApiKey: v))
          : onUpdate(s.copyWith(routmyApiKey: v)),
    ),
  ];
}

/// Connection-field rows for the OpenAI-compatible path. If [useSame]
/// is true only the "Use LLM API" switch is shown — no endpoint or
/// key fields. Otherwise both endpoint URL and API key are visible.
List<Widget> buildOpenaiConnectionFields(
  ImageGenSettings s,
  ValueChanged<ImageGenSettings> onUpdate,
) {
  return [
    rows.ImageGenCheckboxRow(
      label: 'Use LLM API',
      description: 'Use the same endpoint as LLM for image generation',
      value: s.useSameEndpoint,
      onChanged: (v) => onUpdate(s.copyWith(useSameEndpoint: v)),
    ),
    if (!s.useSameEndpoint) ...[
      rows.ImageGenTextFieldItem(
        label: 'Endpoint URL',
        value: s.customEndpoint,
        hint: 'https://api.openai.com/v1',
        onChanged: (v) => onUpdate(s.copyWith(customEndpoint: v)),
      ),
      rows.ImageGenTextFieldItem(
        label: 'API Key',
        value: s.customApiKey,
        obscure: true,
        hint: 'sk-...',
        onChanged: (v) => onUpdate(s.copyWith(customApiKey: v)),
      ),
    ],
  ];
}
