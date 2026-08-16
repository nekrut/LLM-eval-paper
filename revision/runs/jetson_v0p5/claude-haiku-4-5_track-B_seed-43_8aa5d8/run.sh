#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Index reference
if [[ ! -f "$REF.bwt" ]]; then
    bwa index "$REF"
fi

declare -a SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

process_sample() {
    local sample=$1
    local r1="data/raw/${sample}_1.fq.gz"
    local r2="data/raw/${sample}_2.fq.gz"
    local bam_out="$RESULTS_DIR/${sample}.bam"
    local bam_index="$RESULTS_DIR/${sample}.bam.bai"
    local vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
    local vcf_tbi="$RESULTS_DIR/${sample}.vcf.gz.tbi"
    
    # Align reads
    if [[ ! -f "$bam_out" ]]; then
        bwa mem -t "$THREADS" "$REF" "$r1" "$r2" | \
            samtools view -b - | \
            samtools sort -o "$bam_out" -
    fi
    
    # Index BAM
    if [[ ! -f "$bam_index" ]]; then
        samtools index "$bam_out"
    fi
    
    # Call variants
    if [[ ! -f "$vcf_gz" ]]; then
        local vcf_tmp="$RESULTS_DIR/${sample}.vcf"
        lofreq call -f "$REF" -o "$vcf_tmp" "$bam_out"
        bcftools view -O z -o "$vcf_gz" "$vcf_tmp"
        rm "$vcf_tmp"
    fi
    
    # Index VCF
    if [[ ! -f "$vcf_tbi" ]]; then
        tabix -p vcf "$vcf_gz"
    fi
}

# Process samples
for sample in "${SAMPLES[@]}"; do
    process_sample "$sample"
done

# Collapse results
collapsed_tsv="$RESULTS_DIR/collapsed.tsv"

if [[ ! -f "$collapsed_tsv" ]]; then
    echo $'sample\tchrom\tpos\tref\talt\taf' > "$collapsed_tsv"
    
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
        bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%INFO\n" "$vcf_gz" | \
            grep "AF=" | \
            awk -v sample="$sample" -F'\t' '{
                info = $5
                gsub(/.*AF=/, "", info)
                gsub(/;.*/, "", info)
                af = info
                print sample "\t" $1 "\t" $2 "\t" $3 "\t" $4 "\t" af
            }' >> "$collapsed_tsv" || true
    done
fi