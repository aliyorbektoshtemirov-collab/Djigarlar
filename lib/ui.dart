import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';

// ============================================================================
//  Animatsiyalar va umumiy UI qismlari
// ============================================================================

/// Pastdan silliq ko'tarilib paydo bo'ladigan element (ro'yxatlar uchun).
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration duration;
  final double offsetY;
  final bool enabled;
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = const Duration(milliseconds: 420),
    this.offsetY = 18,
    this.enabled = true,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) {
      _c.value = 1;
      return;
    }
    final delay = Duration(milliseconds: 40 * widget.index.clamp(0, 10));
    Future<void>.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      builder: (c, child) => Opacity(
        opacity: curve.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, widget.offsetY * (1 - curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Bosilganda biroz kichrayadigan element — "tirik" his beradi.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.haptic = true,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Silliq sahifa o'tishi (pastdan + xiralashish).
class DjPage<T> extends PageRouteBuilder<T> {
  DjPage(Widget page, {bool fullscreen = false})
      : super(
          fullscreenDialog: fullscreen,
          transitionDuration: const Duration(milliseconds: 340),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (c, a, b) => page,
          transitionsBuilder: (c, a, b, child) {
            final curved = CurvedAnimation(
              parent: a,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.035),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}

Future<T?> push<T>(BuildContext context, Widget page,
        {bool fullscreen = false}) =>
    Navigator.of(context).push<T>(DjPage<T>(page, fullscreen: fullscreen));

// ---------------------------------------------------------------------------
//  Yuklanish effekti
// ---------------------------------------------------------------------------

class Shimmer extends StatefulWidget {
  final double width, height, radius;
  const Shimmer(
      {super.key, this.width = 120, this.height = 14, this.radius = 7});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    return AnimatedBuilder(
      animation: _c,
      builder: (c, _) {
        final t = _c.value * 2 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 0.6, 0),
              end: Alignment(t + 0.6, 0),
              colors: [
                p.hairline,
                p.hairline.withValues(alpha: 0.35),
                p.hairline,
              ],
            ),
          ),
        );
      },
    );
  }
}

class ChatListSkeleton extends StatelessWidget {
  const ChatListSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    return ListView(
      padding: const EdgeInsets.only(top: 6),
      children: [
        for (var i = 0; i < 6; i++)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 5, 14, 5),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: p.hairline, width: 0.8),
            ),
            child: Row(children: [
              const Shimmer(width: 54, height: 54, radius: 27),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Shimmer(width: 130, height: 13),
                  SizedBox(height: 9),
                  Shimmer(width: 190, height: 11),
                ],
              ),
            ]),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  "yozmoqda..." nuqtalari
// ---------------------------------------------------------------------------

class TypingDots extends StatefulWidget {
  final Color color;
  final double size;
  const TypingDots({super.key, required this.color, this.size = 6});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (c, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.6),
                child: Transform.translate(
                  offset: Offset(
                      0,
                      -2.5 *
                          math.sin(
                              (_c.value * 2 * math.pi) - (i * math.pi / 3))
                              .clamp(0.0, 1.0)),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
//  Qo'ng'iroq uchun tarqaluvchi halqalar
// ---------------------------------------------------------------------------

class PulseRing extends StatefulWidget {
  final Widget child;
  final Color color;
  final double size;
  final bool active;
  const PulseRing({
    super.key,
    required this.child,
    required this.color,
    required this.size,
    this.active = true,
  });

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  AnimationController get _c => _ctrl ??= AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (c, child) {
        final rings = <Widget>[];
        for (var i = 0; i < 3; i++) {
          final t = (_c.value + i / 3) % 1.0;
          rings.add(Container(
            width: widget.size * (1 + t * 0.85),
            height: widget.size * (1 + t * 0.85),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.color.withValues(alpha: (1 - t) * 0.45),
                width: 1.4,
              ),
            ),
          ));
        }
        return SizedBox(
          width: widget.size * 1.9,
          height: widget.size * 1.9,
          child: Stack(
            alignment: Alignment.center,
            children: [...rings, child!],
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
//  Doira shaklidagi tugma (qo'ng'iroq boshqaruvi)
// ---------------------------------------------------------------------------

class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color bg;
  final Color fg;
  final double size;
  final String? label;
  final bool glow;
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.bg,
    this.fg = Colors.white,
    this.size = 60,
    this.label,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final btn = PressScale(
      scale: 0.9,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: bg.withValues(alpha: 0.5),
                    blurRadius: 24,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: fg, size: size * 0.44),
      ),
    );
    if (label == null) return btn;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      btn,
      const SizedBox(height: 8),
      Text(
        label!,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.75),
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
//  Bo'sh holat
// ---------------------------------------------------------------------------

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.action});

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: p.card,
              shape: BoxShape.circle,
              border: Border.all(color: p.hairline),
            ),
            child: Icon(icon, size: 34, color: p.faint),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: p.ink),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.45, color: p.muted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Suzuvchi pastki panel (markazda amal tugmasi)
// ---------------------------------------------------------------------------

class DjTab {
  final IconData outline, filled;
  final String label;
  const DjTab(this.outline, this.filled, this.label);
}

class DjTabBar extends StatelessWidget {
  final int index;
  final List<DjTab> tabs;
  final ValueChanged<int> onTap;
  final ValueNotifier<int>? badge;
  final int badgeTab;

  const DjTabBar({
    super.key,
    required this.index,
    required this.tabs,
    required this.onTap,
    this.badge,
    this.badgeTab = 0,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: p.hairline, width: 0.8),
            boxShadow: p.lift,
          ),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++) _item(context, i),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int i) {
    final p = context.dj;
    final sel = i == index;
    final t = tabs[i];
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (i != index) HapticFeedback.selectionClick();
          onTap(i);
        },
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
                horizontal: sel ? 15 : 10, vertical: 9),
            decoration: BoxDecoration(
              color: sel ? p.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Stack(clipBehavior: Clip.none, children: [
                  Icon(
                    sel ? t.filled : t.outline,
                    size: 21,
                    color: sel ? p.inkOn : p.muted,
                  ),
                  if (badge != null && i == badgeTab)
                    Positioned(
                      right: -7,
                      top: -5,
                      child: ValueListenableBuilder<int>(
                        valueListenable: badge!,
                        builder: (c, n, _) => AnimatedScale(
                          scale: n > 0 ? 1 : 0,
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutBack,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 16),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFB8893B),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                  color: sel ? p.ink : p.card, width: 1.4),
                            ),
                            child: Text(
                              n > 99 ? '99+' : '$n',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
                if (sel) ...[
                  const SizedBox(width: 8),
                  Text(
                    t.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: p.inkOn,
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Katta sarlavha (sahifa boshi)
// ---------------------------------------------------------------------------

class BigHeader extends StatelessWidget {
  final String title;
  final String? kicker;
  final Widget? leading;
  final List<Widget> actions;
  const BigHeader({
    super.key,
    required this.title,
    this.kicker,
    this.leading,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 14, 6),
      child: Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kicker != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    kicker!.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.8,
                      color: p.gold,
                    ),
                  ),
                ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.9,
                  height: 1.05,
                  color: p.ink,
                ),
              ),
            ],
          ),
        ),
        ...actions,
      ]),
    );
  }
}

/// Oq doira ichidagi kichik ikonka tugmasi (sarlavha uchun).
class RoundAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  const RoundAction(
      {super.key, required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    final w = PressScale(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        margin: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          color: p.card,
          shape: BoxShape.circle,
          border: Border.all(color: p.hairline, width: 0.8),
        ),
        child: Icon(icon, size: 20, color: p.ink),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// Qidiruv maydoni (oq kapsula).
class SearchPill extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  const SearchPill(
      {super.key,
      required this.hint,
      required this.onChanged,
      this.controller});

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.hairline, width: 0.8),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autocorrect: false,
        style: TextStyle(color: p.ink, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: p.faint, fontWeight: FontWeight.w500),
          prefixIcon: Icon(Icons.search_rounded, color: p.faint, size: 21),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }
}

/// Filtr kapsulalari.
class FilterPills extends StatelessWidget {
  final List<String> items;
  final int selected;
  final ValueChanged<int> onSelect;
  const FilterPills(
      {super.key,
      required this.items,
      required this.selected,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        itemCount: items.length,
        itemBuilder: (c, i) {
          final sel = i == selected;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: PressScale(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? p.ink : p.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: sel ? p.ink : p.hairline, width: 0.8),
                ),
                child: Text(
                  items[i],
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: sel ? p.inkOn : p.muted,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Yuqoridan tushadigan ichki bildirishnoma
// ---------------------------------------------------------------------------

void showTopBanner(
  OverlayState? overlay, {
  required String title,
  required String text,
  Widget? leading,
  VoidCallback? onTap,
}) {
  if (overlay == null || !overlay.mounted) return;
  var removed = false;
  late OverlayEntry entry;
  void kill() {
    if (removed) return;
    removed = true;
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(
    builder: (c) => _TopBanner(
      title: title,
      text: text,
      leading: leading,
      onTap: () {
        kill();
        onTap?.call();
      },
      onDone: kill,
    ),
  );
  overlay.insert(entry);
}

class _TopBanner extends StatefulWidget {
  final String title, text;
  final Widget? leading;
  final VoidCallback onTap;
  final VoidCallback onDone;
  const _TopBanner({
    required this.title,
    required this.text,
    required this.onTap,
    required this.onDone,
    this.leading,
  });

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));

  @override
  void initState() {
    super.initState();
    _c.forward();
    Future<void>.delayed(const Duration(milliseconds: 3600), () async {
      if (!mounted) return;
      await _c.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position:
            Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
                .animate(curve),
        child: FadeTransition(
          opacity: curve,
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: GestureDetector(
                  onTap: widget.onTap,
                  onVerticalDragEnd: (_) => widget.onDone(),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: p.hairline, width: 0.8),
                      boxShadow: p.lift,
                    ),
                    child: Row(children: [
                      if (widget.leading != null) ...[
                        widget.leading!,
                        const SizedBox(width: 11),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                color: p.ink,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              widget.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13, color: p.muted, height: 1.2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right_rounded,
                          size: 20, color: p.faint),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
