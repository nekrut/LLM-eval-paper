#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF=data/ref/chrM.fa
RAW=data/raw
RESULTS=results
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p "$RESULTS"

# Build list of all required output files
required=()
for s in "${SAMPLES[@]}"; do
    required+=("$RESULTS/${s}.bam")
    required+=("$RESULTS/${s}.bam.bai")
    required+=("$RESULTS/${s}.vcf.gz")
    required+=("$RESULTS/${s}.vcf.gz.tbi")
done
required+=("$RESULTS/collapsed.tsv")

# If everything already exists, exit silently
all_exist=true
for f in "${required[@]}"; do
    if [[ ! -f "$f" ]]; then
        all_exist=false
        break
    fi
done
if $all_exist; then
    exit 0
fi

# Process each sample
for sample in "${SAMPLES[@]}"; do
    # Skip if already completed for this sample
    sample_done=true
    for f in "$RESULTS/${sample}.bam" "$RESULTS/${sample}.bam.bai" \
             "$RESULTS/${sample}.vcf.gz" "$RESULTS/${sample}.vcf.gz.tbi"; do
        if [[ ! -f "$f" ]]; then
            sample_done=false
            break
        fi
    done
    if $sample_done; then
        continue
    fi

    fastq1="${RAW}/${sample}_1.fq.gz"
    fastq2="${RAW}/${sample}_2.fq.gz"
    bam="${RESULTS}/${sample}.bam"

    # Align with BWA MEM
    bwa mem -t "$THREADS" -M "$REF" "$fastq1" "$fastq2" |
        samtools view -b -o "$bam"

    # Index BAM
    samtools index "$bam"

    # Variant calling with lofreq
    lofreq call --bam "$bam" --ref "$REF" --output "${RESULTS}/${sample}.vcf" \
                --threads "$THREADS"

    # Compress VCF and index
    bcftools view -Oz -o "${RESULTS}/${sample}.vcf.gz" "${RESULTS}/${sample}.vcf"
    tabix -p vcf "${RESULTS}/${sample}.vcf.gz"

    # Remove intermediate uncompressed VCF
    rm -f "${RESULTS}/${sample}.vcf"
done

# Generate collapsed.tsv
collapse_tmp="${RESULTS}/collapsed.tsv.tmp"
echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapse_tmp"

for sample in "${SAMPLES[@]}"; do
    vcfgz="${RESULTS}/${sample}.vcf.gz"
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t[AF]\n' "$vcfgz" |
        awk -v s="$sample" '{print s "\t" $0}' >> "$collapse_tmp"
done

# Final collapsed table (sorted and deduplicated)
sort -u "$collapse_tmp" > "${RESULTS}/collapsed.tsv"
rm -f "$collapse_tmp"

exit 0