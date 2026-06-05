# PackageSearch

[English](README.md) · **Русский**

**PackageSearch** — десктопное приложение на GTK4/Libadwaita для ALT Linux, позволяющее искать, просматривать и устанавливать пакеты репозиториев **Sisyphus**, **p11**, **p10**, **p9**, **c10f2** и **c9f2**.

<div align="center">
  <img width="922" src="data/screenshots/1.png">
</div>
<div align="center">
  <img width="922" src="data/screenshots/2.png">
</div>
<div align="center">
  <img width="922" src="data/screenshots/3.png">
</div>
<div align="center">
  <img width="922" src="data/screenshots/4.png">
</div>
<div align="center">
  <img width="922" src="data/screenshots/5.png">
</div>

## Возможности

- **Поиск** по всем поддерживаемым веткам в пяти режимах:
  - по имени **исходного пакета**
  - по имени **бинарного пакета**
  - по **файлу** или пути
  - по **сопровождающему**
  - по номеру **задания** (task)
- Умный ввод: нечёткое ранжирование, нормализация кириллической раскладки и живой поиск с задержкой
- **История поиска** и горячие клавиши
- Просмотр полной **информации о пакете**:
  - Имя, версия, релиз, сопровождающий, группа, лицензия и домашняя страница
  - Краткое и полное описание
  - **Бинарные пакеты**, собранные из исходного
  - **Зависимости** в виде интерактивного графа
  - Сравнение **версий по веткам**
  - Разворачиваемый **changelog**
  - Просмотр **spec-файла**
  - **Загрузка** исходных и бинарных RPM
  - **Дистрибутивы**, в состав которых входит пакет
- Раздел **Безопасность**: закрытые уязвимости и известные баги Bugzilla с фильтром по статусу
- **Установка и обновление** пакетов из системного репозитория
- Нативный интерфейс **GNOME/Adwaita** с быстрой и чистой навигацией

## Установка

```bash
apt-get install -y meson ninja-build pkg-config vala gettext libadwaita-devel libjson-glib-devel libsoup3.0-devel libgee0.8-devel blueprint-compiler libgtk4-devel libgee0.8-gir-devel libjson-glib-gir-devel clang cmake gettext gettext-tools gobject-introspection-devel libalt-repo-vala-1-devel libpackagekit-glib-devel
git clone https://altlinux.space/vladislavpetrukhin/PackageSearch PackageSearch
meson setup build --prefix=/usr
meson install -C build
```
