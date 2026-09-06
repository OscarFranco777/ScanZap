import 'package:flutter/material.dart';

/// Tema visual compartido para toda la app — estilo dashboard moderno.
/// Replicar el look-and-feel del HomeScreen en todas las pantallas.
class AppDesign {
  AppDesign._();

  // ─── Colores base ───
  static const navy = Color(0xFF1B2A4A);
  static const accent = Color(0xFF26C6DA);
  static const bg = Color(0xFFF2F4F8);
  static const cardWhite = Colors.white;

  // ─── Colores de módulo ───
  static const orangeLight = Color(0xFFFFF3E0);
  static const orangeIcon = Color(0xFFE65100);
  static const greenLight = Color(0xFFE8F5E9);
  static const greenIcon = Color(0xFF2E7D32);
  static const purpleLight = Color(0xFFF3E5F5);
  static const purpleIcon = Color(0xFF7B1FA2);
  static const tealLight = Color(0xFFE0F7FA);
  static const tealIcon = Color(0xFF00838F);
  static const blueLight = Color(0xFFE3F2FD);
  static const blueIcon = Color(0xFF1565C0);

  // ─── Status colors ───
  static const statusDraft = Color(0xFFFFA726);
  static const statusSubmitted = Color(0xFF66BB6A);
  static const statusCancelled = Color(0xFFEF5350);

  // ══════════════════════════════════════════════════════════════
  // HEADER NAVY — reutilizable en todas las pantallas
  // ══════════════════════════════════════════════════════════════

  static Widget buildHeader({
    required String title,
    required IconData icon,
    String? subtitle,
    List<Widget>? actions,
    VoidCallback? onBack,
    bool showBack = true,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        color: navy,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (showBack)
              GestureDetector(
                onTap: onBack ?? () {},
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                ),
              ),
            if (showBack) const SizedBox(width: 12),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
            if (actions != null) ...actions,
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // STATS CARD — tarjeta oscura con métricas
  // ══════════════════════════════════════════════════════════════

  static Widget buildStatsCard({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: navy,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: navy.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  static Widget buildStatRow({required List<Widget> items}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: items[i]),
          ],
        ],
      ),
    );
  }

  static Widget statBox({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    bool smallValue = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.5),
                    letterSpacing: 0.6,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: smallValue ? 11 : 16,
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // LIST CARD — tarjeta moderna para items de lista
  // ══════════════════════════════════════════════════════════════

  static Widget buildListCard({
    required BuildContext context,
    required Widget child,
    VoidCallback? onTap,
    Color? accentColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardWhite,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (accentColor ?? navy).withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // STATUS BADGE
  // ══════════════════════════════════════════════════════════════

  static Widget statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // EMPTY STATE
  // ══════════════════════════════════════════════════════════════

  static Widget emptyState({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: Colors.grey[400]),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SECTION TITLE
  // ══════════════════════════════════════════════════════════════

  static Widget sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.grey[500],
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // FLOATING ACTION BUTTON — consistente
  // ══════════════════════════════════════════════════════════════

  static FloatingActionButton fab({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    Color? color,
  }) {
    return FloatingActionButton.extended(
      onPressed: onPressed,
      backgroundColor: color ?? navy,
      foregroundColor: Colors.white,
      elevation: 4,
      icon: Icon(icon),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // AVATAR con iniciales/ícono
  // ══════════════════════════════════════════════════════════════

  static Widget circleAvatar({
    required IconData icon,
    required Color bgColor,
    required Color iconColor,
    double size = 40,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: size * 0.45, color: iconColor),
    );
  }
}
