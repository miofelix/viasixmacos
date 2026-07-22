package dev.viasix.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Design tokens mirrored from the macOS [VisualStyle] so Android screens share
 * spacing, radius, and semantic colors with the desktop shell.
 */
@Immutable
data class ViaSixColors(
    val accent: Color,
    val positive: Color,
    val warning: Color,
    val negative: Color,
    val pageBackground: Color,
    val sidebarBackground: Color,
    val surface: Color,
    val elevatedSurface: Color,
    val subtleFill: Color,
    val surfaceBorder: Color,
)

object VisualStyle {
    val spacing4: Dp = 4.dp
    val spacing8: Dp = 8.dp
    val spacing12: Dp = 12.dp
    val spacing16: Dp = 16.dp
    val spacing20: Dp = 20.dp
    val spacing24: Dp = 24.dp

    val radiusSmall: Dp = 6.dp
    val radiusMedium: Dp = 8.dp
    val radiusLarge: Dp = 10.dp

    val pageHeaderHeight: Dp = 56.dp
    val settingsRowHeight: Dp = 52.dp
    val pageHorizontalPadding: Dp = 12.dp
    val pageVerticalPadding: Dp = 10.dp
    val controlHeight: Dp = 40.dp

    val accentLight = Color(0xFF007AFF)
    val accentDark = Color(0xFF0A84FF)
    val positive = Color(0xFF34C759)
    val warning = Color(0xFFFF9500)
    val negative = Color(0xFFFF3B30)

    fun colors(dark: Boolean): ViaSixColors =
        if (dark) {
            ViaSixColors(
                accent = accentDark,
                positive = positive,
                warning = warning,
                negative = negative,
                pageBackground = Color(0xFF1E2028),
                sidebarBackground = Color(0xFF2E303D),
                surface = Color(0xFF282A36),
                elevatedSurface = Color(0xFF30323F),
                subtleFill = Color.White.copy(alpha = 0.045f),
                surfaceBorder = Color.White.copy(alpha = 0.12f),
            )
        } else {
            ViaSixColors(
                accent = accentLight,
                positive = positive,
                warning = warning,
                negative = negative,
                pageBackground = Color(0xFFF5F5F5),
                sidebarBackground = Color(0xFFF9F9F9),
                surface = Color.White,
                elevatedSurface = Color(0xFFF9F9F9),
                subtleFill = Color.Black.copy(alpha = 0.045f),
                surfaceBorder = Color.Black.copy(alpha = 0.12f),
            )
        }
}

enum class AppTone {
    Accent,
    Positive,
    Warning,
    Negative,
    Neutral,
}

@Composable
fun AppTone.color(colors: ViaSixColors = LocalViaSixColors.current): Color =
    when (this) {
        AppTone.Accent -> colors.accent
        AppTone.Positive -> colors.positive
        AppTone.Warning -> colors.warning
        AppTone.Negative -> colors.negative
        AppTone.Neutral -> MaterialTheme.colorScheme.onSurfaceVariant
    }

val LocalViaSixColors =
    staticCompositionLocalOf {
        VisualStyle.colors(dark = false)
    }

private val LightScheme =
    lightColorScheme(
        primary = VisualStyle.accentLight,
        onPrimary = Color.White,
        secondary = VisualStyle.accentLight,
        background = Color(0xFFF5F5F5),
        surface = Color.White,
        onBackground = Color(0xFF1C1C1E),
        onSurface = Color(0xFF1C1C1E),
        onSurfaceVariant = Color(0xFF6C6C70),
        outline = Color.Black.copy(alpha = 0.12f),
        error = VisualStyle.negative,
    )

private val DarkScheme =
    darkColorScheme(
        primary = VisualStyle.accentDark,
        onPrimary = Color.White,
        secondary = VisualStyle.accentDark,
        background = Color(0xFF1E2028),
        surface = Color(0xFF282A36),
        onBackground = Color(0xFFF2F2F7),
        onSurface = Color(0xFFF2F2F7),
        onSurfaceVariant = Color(0xFFAEAEB2),
        outline = Color.White.copy(alpha = 0.12f),
        error = VisualStyle.negative,
    )

@Composable
fun ViaSixTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val viaSixColors = VisualStyle.colors(darkTheme)
    androidx.compose.runtime.CompositionLocalProvider(
        LocalViaSixColors provides viaSixColors,
    ) {
        MaterialTheme(
            colorScheme = if (darkTheme) DarkScheme else LightScheme,
            content = content,
        )
    }
}
