use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use clap::{Parser, Subcommand};
use db_dump::categories::CategoryId;
use db_dump::crates::{CrateId, Row};
use db_dump::keywords::KeywordId;
use db_dump::versions::VersionId;
use indicatif::{ProgressBar, ProgressStyle};
use rayon::prelude::*;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::cmp::Reverse;
use std::collections::btree_map::Entry;
use std::collections::{BTreeMap as Map, BTreeSet as Set};
use std::fs::{self, File};
use std::io::Write;
use std::path::Path;
use std::sync::Mutex;

#[derive(Parser)]
#[command(name = "crates-dumper")]
#[command(about = "Process crates.io database dumps into JSON")]
#[command(version = "0.0.1")]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// Number of threads to use for parallel processing
    #[arg(short = 'j', long, default_value_t = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4))]
    threads: usize,

    /// Verbose output
    #[arg(short, long)]
    verbose: bool,

    /// Quiet output (suppress progress bars and info messages)
    #[arg(short, long)]
    quiet: bool,
}

#[derive(Subcommand)]
enum Commands {
    /// Download and process the latest database dump
    Download {
        /// Output file for JSON data
        #[arg(short, long, default_value = "crates.json")]
        output: String,

        /// Path to save the downloaded dump file
        #[arg(short, long, default_value = "db-dump.tar.gz")]
        dump_file: String,

        /// Force download even if file exists
        #[arg(short, long)]
        force: bool,

        /// Only download, don't process
        #[arg(long)]
        download_only: bool,
    },
    /// Process an existing local database dump file
    Process {
        /// Path to the local db-dump.tar.gz file
        #[arg(short, long, default_value = "db-dump.tar.gz")]
        input: String,

        /// Output file for JSON data
        #[arg(short, long, default_value = "crates.json")]
        output: String,
    },
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Crate {
    pub name: String,
    pub repository: Option<String>,
    pub homepage: Option<String>,
    pub documentation: Option<String>,
    pub description: String,
    pub version: Option<String>,
    pub version_alpha: Option<String>,
    pub categories: Vec<String>,
    pub keywords: Vec<String>,
    pub num_versions: u32,
    pub dependency_count: u32,
    pub total_downloads: u64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DumpData {
    pub generated_at: DateTime<Utc>,
    pub crates: Vec<Crate>,
}

struct Config {
    verbose: bool,
    quiet: bool,
    threads: usize,
}

impl Config {
    fn log(&self, message: &str) {
        if !self.quiet {
            println!("{}", message);
        }
    }

    fn log_verbose(&self, message: &str) {
        if self.verbose && !self.quiet {
            println!("🔍 {}", message);
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // Set up thread pool
    rayon::ThreadPoolBuilder::new()
        .num_threads(cli.threads)
        .build_global()
        .context("Failed to initialize thread pool")?;

    let config = Config {
        verbose: cli.verbose,
        quiet: cli.quiet,
        threads: cli.threads,
    };

    config.log_verbose(&format!(
        "Using {} threads for parallel processing",
        cli.threads
    ));

    match cli.command {
        Commands::Download {
            output,
            dump_file,
            force,
            download_only,
        } => {
            if !force && Path::new(&dump_file).exists() {
                config.log(&format!("📁 Database dump already exists at {}", dump_file));
                config.log("💡 Use --force to download anyway, or use 'process' command to use existing file");
            } else {
                download_dump(&dump_file, &config).await?;
            }

            if !download_only {
                process_dump(&dump_file, &output, &config)?;
            } else {
                config.log(&format!("💾 Download complete: {}", dump_file));
            }
        }
        Commands::Process { input, output } => {
            if !Path::new(&input).exists() {
                anyhow::bail!("❌ Input file '{}' does not exist", input);
            }
            process_dump(&input, &output, &config)?;
        }
    }
    Ok(())
}

async fn download_dump(output_path: &str, config: &Config) -> Result<()> {
    let url = "https://static.crates.io/db-dump.tar.gz";
    let client = Client::builder()
        .timeout(std::time::Duration::from_secs(300))
        .build()
        .context("Failed to create HTTP client")?;

    config.log("🔍 Checking latest database dump...");

    // Get file size for progress bar
    let head_resp = client
        .head(url)
        .send()
        .await
        .context("Failed to get file info")?;

    let total_size = head_resp
        .headers()
        .get("content-length")
        .and_then(|h| h.to_str().ok())
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(0);

    config.log(&format!(
        "📥 Downloading database dump ({:.2} MB)...",
        total_size as f64 / 1_000_000.0
    ));

    let response = client
        .get(url)
        .send()
        .await
        .context("Failed to start download")?;

    if !response.status().is_success() {
        anyhow::bail!("Failed to download: HTTP {}", response.status());
    }

    // Setup progress bar
    let pb = if config.quiet {
        ProgressBar::hidden()
    } else {
        let pb = ProgressBar::new(total_size);
        pb.set_style(
            ProgressStyle::with_template(
                "{spinner:.green} [{elapsed_precise}] [{wide_bar:.cyan/blue}] {bytes}/{total_bytes} ({bytes_per_sec}, {eta})"
            )?
            .progress_chars("#>-"),
        );
        pb
    };

    let mut file = File::create(output_path).context("Failed to create output file")?;

    let mut downloaded = 0u64;
    let mut stream = response.bytes_stream();

    use futures_util::StreamExt;
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.context("Error while downloading")?;
        file.write_all(&chunk)
            .context("Error while writing to file")?;
        downloaded += chunk.len() as u64;
        pb.set_position(downloaded);
    }

    pb.finish_with_message("✅ Download complete!");
    config.log(&format!("💾 Saved to {}", output_path));

    Ok(())
}

fn normalize_string(s: &str) -> String {
    s.trim()
        .to_lowercase()
        .replace([' ', '\n', '\r', '\t'], "-")
        .replace("--", "-")
        .trim_matches('-')
        .to_string()
}

fn clean_string(s: &str) -> String {
    s.replace(['\n', '\r'], " ").trim().to_string()
}

fn clean_optional_string(s: &Option<String>) -> Option<String> {
    s.as_ref()
        .map(|s| clean_string(s))
        .filter(|s| !s.is_empty())
}

fn process_dump(input_path: &str, output_path: &str, config: &Config) -> Result<()> {
    config.log("🔄 Processing database dump...");
    let start_time = std::time::Instant::now();

    let pb = if config.quiet {
        ProgressBar::hidden()
    } else {
        let pb = ProgressBar::new_spinner();
        pb.set_style(
            ProgressStyle::with_template("{spinner:.green} {msg}")
                .unwrap()
                .tick_strings(&["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]),
        );
        pb
    };

    pb.set_message("Loading crates data...");
    config.log_verbose("Initializing data structures...");

    // Pre-allocate with reasonable capacities to reduce allocations
    let mut most_recent = Map::new();
    let mut crates = Set::new();
    let mut dependencies = Vec::with_capacity(1_000_000); // Typical size
    let mut crate_keywords: Map<CrateId, Vec<KeywordId>> = Map::new();
    let mut crate_categories: Map<CrateId, Vec<CategoryId>> = Map::new();
    let mut all_keywords: Map<KeywordId, String> = Map::new();
    let mut all_categories: Map<CategoryId, String> = Map::new();
    let mut version_count = Map::<CrateId, u32>::new();
    let mut libs = Set::<CrateId>::new();
    let mut stable_versions = Map::<CrateId, semver::Version>::new();
    let mut versions = Map::<CrateId, semver::Version>::new();
    let mut version_downloads = Map::<VersionId, u64>::new();

    pb.set_message("Loading database dump...");
    config.log_verbose("Reading database dump file...");

    let load_start = std::time::Instant::now();

    db_dump::Loader::new()
        .crates(|row| {
            crates.insert(row);
        })
        .dependencies(|row| dependencies.push(row))
        .versions(|row| {
            // Store download counts for each version
            version_downloads.insert(row.id, row.downloads);

            // row.num is already a semver::Version
            let version = &row.num;
            match version.pre.is_empty() {
                true => {
                    stable_versions
                        .entry(row.crate_id)
                        .and_modify(|old_version| {
                            if *old_version < *version {
                                *old_version = version.clone();
                            }
                        })
                        .or_insert(version.clone());
                }
                false => {
                    versions
                        .entry(row.crate_id)
                        .and_modify(|old_version| {
                            if *old_version < *version {
                                *old_version = version.clone();
                            }
                        })
                        .or_insert(version.clone());
                }
            };

            if row.has_lib {
                libs.insert(row.crate_id);
            }

            // Use created_at for most recent determination
            match most_recent.entry(row.crate_id) {
                Entry::Vacant(entry) => {
                    entry.insert(row);
                }
                Entry::Occupied(mut entry) => {
                    if row.created_at > entry.get().created_at {
                        entry.insert(row);
                    }
                }
            }
        })
        .default_versions(|row| {
            version_count.insert(row.crate_id, row.num_versions.unwrap_or_default());
        })
        .crates_keywords(|row| {
            crate_keywords
                .entry(row.crate_id)
                .or_default()
                .push(row.keyword_id);
        })
        .crates_categories(|row| {
            crate_categories
                .entry(row.crate_id)
                .or_default()
                .push(row.category_id);
        })
        .keywords(|row| {
            all_keywords.insert(row.id, row.keyword.clone());
        })
        .categories(|row| {
            all_categories.insert(row.id, row.category.clone());
        })
        .load(input_path)
        .context("Failed to load database dump")?;

    config.log_verbose(&format!(
        "Database loading took {:.2}s",
        load_start.elapsed().as_secs_f64()
    ));

    pb.set_message("Processing crates...");
    config.log_verbose(&format!(
        "Loaded {} crates, {} dependencies",
        crates.len(),
        dependencies.len()
    ));

    let crates = crates
        .into_iter()
        .filter(|c| libs.contains(&c.id))
        .collect::<Set<Row>>();

    config.log_verbose(&format!("Filtered to {} library crates", crates.len()));

    // Set of version ids which are the most recently published of their crate.
    let most_recent_versions = Set::from_iter(most_recent.values().map(|version| version.id));

    pb.set_message("Calculating dependencies...");
    config.log_verbose("Calculating dependency counts...");

    let dep_start = std::time::Instant::now();

    // Use parallel processing for dependency calculation
    let count = Mutex::new(Map::<CrateId, usize>::new());
    let unique_edges = Mutex::new(Set::<(VersionId, CrateId)>::new());

    // Process dependencies in parallel chunks
    dependencies.par_chunks(10_000).for_each(|chunk| {
        let mut local_count = Map::<CrateId, usize>::new();
        let mut local_edges = Set::<(VersionId, CrateId)>::new();

        for dep in chunk {
            if most_recent_versions.contains(&dep.version_id)
                && local_edges.insert((dep.version_id, dep.crate_id))
            {
                *local_count.entry(dep.crate_id).or_default() += 1;
            }
        }

        // Merge local results into global
        {
            let mut global_count = count.lock().unwrap();
            let mut global_edges = unique_edges.lock().unwrap();

            for (edge_key, edge_val) in local_edges {
                if global_edges.insert((edge_key, edge_val)) {
                    *global_count.entry(edge_val).or_default() += 1;
                }
            }
        }
    });

    let mut count = count.into_inner().unwrap();

    // Ensure all crates have an entry
    for crat in &crates {
        count.entry(crat.id).or_insert(0);
    }

    config.log_verbose(&format!(
        "Dependency calculation took {:.2}s",
        dep_start.elapsed().as_secs_f64()
    ));

    pb.set_message("Calculating total downloads...");
    config.log_verbose("Calculating download statistics...");

    // Calculate total downloads more efficiently
    let total_downloads: Map<CrateId, u64> = most_recent
        .par_iter()
        .map(|(crate_id, version)| {
            let downloads = version_downloads.get(&version.id).copied().unwrap_or(0);
            (*crate_id, downloads)
        })
        .collect();

    pb.set_message("Sorting crates...");
    config.log_verbose("Sorting crates by dependency count...");

    // Sort all crates by dependency count descending
    let mut all_crates: Vec<_> = count.into_iter().collect();
    all_crates.par_sort_unstable_by_key(|&(_, count)| Reverse(count));

    pb.set_message("Building output data...");
    config.log_verbose("Building final output structure...");

    let build_start = std::time::Instant::now();

    // Process crates in parallel
    let results: Vec<Option<Crate>> = all_crates
        .par_iter()
        .filter_map(|(id, dependency_count)| {
            crates.get(id).map(|crat| (*id, *dependency_count, crat))
        })
        .map(|(_id, dependency_count, crat)| {
            // Check mandatory fields and skip if any are missing/empty
            let clean_name = clean_string(&crat.name);
            let clean_description = clean_string(&crat.description);

            // Check if we have at least one version (stable or alpha)
            let stable_version = stable_versions.get(&crat.id).map(|v| v.to_string());
            let alpha_version = versions.get(&crat.id).map(|v| v.to_string());
            let has_version = stable_version.is_some() || alpha_version.is_some();

            // Check all mandatory fields
            let missing_fields = vec![
                if clean_name.is_empty() {
                    Some("name")
                } else {
                    None
                },
                if clean_description.is_empty() {
                    Some("description")
                } else {
                    None
                },
                if !has_version { Some("version") } else { None },
            ]
            .into_iter()
            .flatten()
            .collect::<Vec<_>>();

            if !missing_fields.is_empty() {
                if config.verbose {
                    eprintln!(
                        "⚠️  Skipping crate '{}': missing {}",
                        crat.name,
                        missing_fields.join(", ")
                    );
                }
                return None;
            }

            Some(Crate {
                dependency_count: dependency_count as u32,
                name: clean_name,
                repository: clean_optional_string(&crat.repository),
                homepage: clean_optional_string(&crat.homepage),
                documentation: clean_optional_string(&crat.documentation),
                description: clean_description,
                version: stable_version,
                version_alpha: alpha_version,
                categories: crate_categories
                    .get(&crat.id)
                    .map(|category_ids| {
                        category_ids
                            .iter()
                            .filter_map(|id| all_categories.get(id))
                            .map(|cat| normalize_string(cat))
                            .filter(|cat| !cat.is_empty())
                            .collect()
                    })
                    .unwrap_or_default(),
                keywords: crate_keywords
                    .get(&crat.id)
                    .map(|keyword_ids| {
                        keyword_ids
                            .iter()
                            .filter_map(|id| all_keywords.get(id))
                            .map(|kw| normalize_string(kw))
                            .filter(|kw| !kw.is_empty())
                            .collect()
                    })
                    .unwrap_or_default(),
                num_versions: version_count.get(&crat.id).copied().unwrap_or_default(),
                total_downloads: total_downloads.get(&crat.id).copied().unwrap_or(0),
            })
        })
        .collect();

    let processed_crates: Vec<Crate> = results.into_iter().flatten().collect();
    let skipped_count = all_crates.len() - processed_crates.len();

    config.log_verbose(&format!(
        "Output building took {:.2}s",
        build_start.elapsed().as_secs_f64()
    ));

    let dump_data = DumpData {
        generated_at: Utc::now(),
        crates: processed_crates,
    };

    pb.set_message("Writing JSON output...");
    config.log_verbose("Serializing and writing JSON...");

    let json_start = std::time::Instant::now();
    let json =
        serde_json::to_string_pretty(&dump_data).context("Failed to serialize data to JSON")?;

    fs::write(output_path, json).context("Failed to write output file")?;

    config.log_verbose(&format!(
        "JSON serialization took {:.2}s",
        json_start.elapsed().as_secs_f64()
    ));

    pb.finish_with_message("✅ Processing complete!");

    let total_time = start_time.elapsed();
    config.log(&format!("📊 Processed {} crates", dump_data.crates.len()));
    if skipped_count > 0 {
        config.log(&format!(
            "⚠️  Skipped {} crates with missing mandatory fields",
            skipped_count
        ));
    }
    config.log(&format!("💾 Output saved to {}", output_path));
    config.log(&format!(
        "⏱️  Total processing time: {:.2}s",
        total_time.as_secs_f64()
    ));

    if config.verbose {
        config.log(&format!("🧵 Used {} threads", config.threads));
    }

    Ok(())
}
