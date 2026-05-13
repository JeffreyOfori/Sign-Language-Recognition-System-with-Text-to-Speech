import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/gemini_service.dart';
import '../theme.dart';

class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.prediction,
    required this.busy,
    required this.ttsOn,
    required this.onToggleTts,
  });

  final SignPrediction? prediction;
  final bool busy;
  final bool ttsOn;
  final VoidCallback onToggleTts;

  @override
  Widget build(BuildContext context) {
    final p = prediction;
    final hasSign = p != null && p.sign != '—' && p.sign != 'NONE';
    final headline = hasSign
        ? (p.gloss.isNotEmpty ? p.gloss : p.sign)
        : (busy ? 'Reading sign…' : 'Show a sign');
    final confidence = (p?.confidence ?? 0).clamp(0.0, 1.0).toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: AppColors.cardGlass,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: hasSign ? 0.15 : 0.05),
                blurRadius: 24,
                spreadRadius: -4,
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ConfidenceRing(value: confidence, busy: busy, hasSign: hasSign),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.15),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        headline,
                        key: ValueKey(headline),
                        style: TextStyle(
                          color: hasSign ? Colors.white : AppColors.muted,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (hasSign) ...[
                      Row(
                        children: [
                          _Tag(label: p.sign),
                          if (p.note.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                p.note,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ] else
                      Text(
                        busy ? 'Analyzing latest frame' : 'Auto-recognize is on',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: ttsOn ? 'Mute' : 'Speak result',
                style: IconButton.styleFrom(
                  backgroundColor: ttsOn
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  foregroundColor: ttsOn ? AppColors.accent : AppColors.muted,
                ),
                icon: Icon(ttsOn ? Icons.volume_up_rounded : Icons.volume_off_rounded),
                onPressed: onToggleTts,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfidenceRing extends StatelessWidget {
  const _ConfidenceRing({required this.value, required this.busy, required this.hasSign});
  final double value;
  final bool busy;
  final bool hasSign;

  @override
  Widget build(BuildContext context) {
    final color = !hasSign
        ? AppColors.muted
        : value >= 0.7
            ? AppColors.success
            : value >= 0.4
                ? AppColors.warn
                : AppColors.danger;
    final pct = (value * 100).round();

    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              value: busy && !hasSign ? null : value,
              strokeWidth: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Text(
            hasSign ? '$pct%' : (busy ? '…' : '—'),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4), width: 0.6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.accentSoft,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
