Drop the six TTFs here (or run Scripts/fetch-fonts.sh from the project root):

  Fraunces-SemiBold.ttf, Fraunces-Bold.ttf
  PublicSans-Regular.ttf, PublicSans-SemiBold.ttf, PublicSans-Bold.ttf
  IBMPlexMono-Medium.ttf

They are already declared in Info.plist. Without them the app runs fine on
New York serif / SF / SF Mono system fallbacks (Theme.swift handles it).
