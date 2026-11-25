# Android/Gradle on a worker

## Maven Central rate limits (HTTP 429)

Maven Central rate-limits the workers' egress addresses. A Gradle run then fails with
`Could not GET 'https://repo.maven.apache.org/...' Received status code 429`, and Robolectric
tests fail with `Failed to fetch maven artifact org.robolectric:android-all-instrumented:...`
(Robolectric downloads its Android runtimes itself, at test time). Retrying does not help: the
same address stays limited for a while (seen on 2026-11-25 with three workers in a row).

Fetch what is missing from Google's Maven Central mirror on the worker itself (no transfer over
the home link) into `~/.m2`, and let Gradle look there for that group. Robolectric checks `~/.m2`
on its own. Use the versions the failure names:

```bash
m=https://maven-central.storage-download.googleapis.com/maven2/org/robolectric
r=~/.m2/repository/org/robolectric
for p in nativeruntime-dist-compat/1.0.0 \
  android-all-instrumented/9-robolectric-4913185-2-i4 \
  android-all-instrumented/13-robolectric-9030017-i4 \
  android-all-instrumented/5.1.1_r9-robolectric-r2-i4
do
  a=${p%%/*}; v=${p#*/}; mkdir -p "$r/$p"
  for e in jar pom; do curl -fsSL -o "$r/$p/$a-$v.$e" "$m/$p/$a-$v.$e"; done
done
cat > ~/local.gradle <<'G'
settingsEvaluated { settings ->
    settings.dependencyResolutionManagement.repositories.mavenLocal { content { includeGroup("org.robolectric") } }
}
allprojects { repositories { mavenLocal { content { includeGroup("org.robolectric") } } } }
G
```

Then pass `--init-script ~/local.gradle` to `./gradlew`. Check a downloaded jar's SHA-256 against
the project's `gradle/verification-metadata.xml` when it has one. Copying a jar into
`~/.gradle/caches/modules-2/files-2.1/` does not work: Gradle ignores files its metadata index does
not know, even with `--offline`.
