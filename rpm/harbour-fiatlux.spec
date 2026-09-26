Name:       harbour-fiatlux
Summary:    Light meter for film photography
Version:    1.0
Release:    1
License:    MIT
URL:        https://github.com/munksh/FiatLux
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  desktop-file-utils

# libfiatluxcamera2.so is an Android (Bionic) library, loaded through libhybris
# from /usr/libexec/droid-hybris. Its NDK dependencies come from the Android
# side of the phone, not from Sailfish packages, so RPM must not require them.
# The same exclusions RAWfish makes for its copy.
%global __requires_exclude_from ^.*/usr/libexec/droid-hybris/system/lib64/libfiatluxcamera2\\.so$
%global __provides_exclude_from ^.*/usr/libexec/droid-hybris/system/lib64/libfiatluxcamera2\\.so$
%global __requires_exclude ^(libandroid\\.so.*|libcamera2ndk\\.so.*|libmediandk\\.so.*|libnativewindow\\.so.*|liblog\\.so.*|libdl_android\\.so.*)$
# The Android library has no GNU build ID, so a missing one must not stop the build.
%undefine _missing_build_ids_terminate_build

%description
A light meter for analogue film photography. It meters the light and offers
exposure pairs matched to the cameras, lenses and film you actually own.

%prep
%setup -q -n %{name}-%{version}

%build
%qmake5 APP_VERSION=%{version}
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
make install INSTALL_ROOT=%{buildroot}
desktop-file-install --delete-original --dir %{buildroot}%{_datadir}/applications %{buildroot}%{_datadir}/applications/*.desktop

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png
%{_libexecdir}/%{name}
%{_libexecdir}/droid-hybris/system/lib64/libfiatluxcamera2.so
%license %{_datadir}/licenses/%{name}/LICENSE
%license %{_datadir}/licenses/%{name}/LICENSE.RAWfish
