package com.htmlkeep.community.ui

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

object AppPreferences {
    private const val STORE_NAME = "app_preferences"
    private const val KEY_LANGUAGE = "language"
    private const val KEY_APPEARANCE = "appearance"
    private const val KEY_HOME_DISPLAY_MODE = "home_display_mode"
    private const val KEY_EXPERT_MODE_ENABLED = "expert_mode_enabled"

    val languages = listOf(
        Language("automatic", "自动", null, false),
        Language("en", "English", "en", false),
        Language("zh-Hans", "简体中文", "zh-CN", false),
        Language("zh-Hant", "繁體中文", "zh-TW", false),
        Language("ja", "日本語", "ja", false),
        Language("de", "Deutsch", "de", false),
        Language("fr", "Français", "fr", false),
        Language("es", "Español", "es", false),
        Language("ko", "한국어", "ko", false),
        Language("it", "Italiano", "it", false),
        Language("nl", "Nederlands", "nl", false),
        Language("pt-BR", "Português", "pt-BR", false),
        Language("ru", "Русский", "ru", false),
        Language("ar", "العربية", "ar", true),
        Language("hi", "हिन्दी", "hi", false),
        Language("bn", "বাংলা", "bn", false),
        Language("ur", "اردو", "ur", true)
    )

    val appearances = listOf(
        Appearance("automatic", "自动"),
        Appearance("light", "浅色"),
        Appearance("dark", "深色")
    )

    val homeDisplayModes = listOf(
        HomeDisplayMode("list", "列表"),
        HomeDisplayMode("grid", "网格")
    )

    fun selectedLanguage(context: Context): Language {
        val rawValue = store(context).getString(KEY_LANGUAGE, null)
        return languages.firstOrNull { it.rawValue == rawValue } ?: languages.first()
    }

    fun setLanguage(context: Context, language: Language) {
        store(context).edit().putString(KEY_LANGUAGE, language.rawValue).apply()
    }

    fun selectedAppearance(context: Context): Appearance {
        val rawValue = store(context).getString(KEY_APPEARANCE, null)
        return appearances.firstOrNull { it.rawValue == rawValue } ?: appearances.first()
    }

    fun setAppearance(context: Context, appearance: Appearance) {
        store(context).edit().putString(KEY_APPEARANCE, appearance.rawValue).apply()
    }

    fun selectedHomeDisplayMode(context: Context): HomeDisplayMode {
        val rawValue = store(context).getString(KEY_HOME_DISPLAY_MODE, null)
        return homeDisplayModes.firstOrNull { it.rawValue == rawValue } ?: homeDisplayModes.first()
    }

    fun setHomeDisplayMode(context: Context, mode: HomeDisplayMode) {
        store(context).edit().putString(KEY_HOME_DISPLAY_MODE, mode.rawValue).apply()
    }

    fun isExpertModeEnabled(context: Context): Boolean {
        if (!store(context).contains(KEY_EXPERT_MODE_ENABLED)) {
            return isDebuggable(context)
        }
        return store(context).getBoolean(KEY_EXPERT_MODE_ENABLED, isDebuggable(context))
    }

    fun setExpertModeEnabled(context: Context, isEnabled: Boolean) {
        store(context).edit().putBoolean(KEY_EXPERT_MODE_ENABLED, isEnabled).apply()
    }

    fun localizedContext(context: Context): Context {
        val tag = selectedLanguage(context).localeTag ?: return context
        val locale = Locale.forLanguageTag(tag)
        Locale.setDefault(locale)
        val configuration = Configuration(context.resources.configuration)
        configuration.setLocale(locale)
        configuration.setLayoutDirection(locale)
        return context.createConfigurationContext(configuration)
    }

    fun isRightToLeft(context: Context): Boolean {
        val selected = selectedLanguage(context)
        if (selected.localeTag != null) return selected.isRightToLeft
        return context.resources.configuration.layoutDirection == android.view.View.LAYOUT_DIRECTION_RTL
    }

    private fun isDebuggable(context: Context): Boolean {
        return (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private fun store(context: Context) = context.getSharedPreferences(STORE_NAME, Context.MODE_PRIVATE)

    data class Language(
        val rawValue: String,
        val displayName: String,
        val localeTag: String?,
        val isRightToLeft: Boolean
    )

    data class Appearance(
        val rawValue: String,
        val displayName: String
    )

    data class HomeDisplayMode(
        val rawValue: String,
        val displayName: String
    )
}
