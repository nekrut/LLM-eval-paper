#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Index reference if not already indexed
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    bam="$RESULTS_DIR/${sample}.bam"
    vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
    
    # Skip if all outputs exist and are non-empty
    if [[ -s "$bam" && -s "${bam}.bai" && -s "$vcf_gz" && -s "${vcf_gz}.tbi" ]]; then
        continue
    fi
    
    # Align reads
    bwa mem -t "$THREADS" "$REF" \
        "${RAW_DIR}/${sample}_1.fq.gz" \
        "${RAW_DIR}/${sample}_2.fq.gz" | \
    samtools view -bS - | \
    samtools sort -@ "$THREADS" -o "$bam" -
    
    # Index BAM
    samtools index "$bam"
    
    # Mark duplicates and base quality recalibration with lofreq
    lofreq markdup -r "$REF" -o "$bam" "$bam"
    
    # Call variants with lofreq
    lofreq viterbi -f "$REF" -o "${vcf_gz%.gz}" "$bam" | \
        bcftools view -Oz -o "$vcf_gz"
    
    tabix -p vcf "$vcf_gz"
done

# Create collapsed TSV with all samples' variants
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${SAMPLES[@]}"; do
        vcf="$RESULTS_DIR/${sample}.vcf.gz"
        if [[ -s "$vcf" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t[%ALT\t%AD]\n' "$vcf" | \
                awk -v sample="$sample" 'BEGIN{FS="\t"} {
                    chrom=$1; pos=$2; ref=$3; alt=$4; ad=$5;
                    if (ad ~ /,/) {
                        split(ad, parts, ",");
                        alt_count = parts[2] + 0;
                        total = parts[1] + alt_count;
                        af = (total > 0) ? alt_count/total : 0;
                    } else {
                        alt_count = ad+0;
                        total = alt_count;
                        af = (total > 0) ? alt_count/total : 0;
                    }
                    printf "%s\t%s\t%s\t%s\t%.6f\n", sample, chrom, pos, ref, alt, af;
                }'
        fi
    done | sort -t$'\t' -k1,1 -k2,2n -k3,3n
} > "$RESULTS_DIR/collapsed.tsv"