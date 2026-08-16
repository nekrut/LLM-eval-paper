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
    
    # Call variants with lofreq
    lofreq call -f "$REF" -r "$RESULTS_DIR/${sample}.vcf.gz" -t "$THREADS" "$bam"
    
    # Compress and index VCF if needed (lofreq may output plain vcf)
    if [[ ! -f "${vcf_gz}" ]]; then
        samtools view -b "$bam" | lofreq call -f "$REF" -t "$THREADS" - > "${RESULTS_DIR}/${sample}.vcf"
        bgzip -c "${RESULTS_DIR}/${sample}.vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "${RESULTS_DIR}/${sample}.vcf"
    else
        # Ensure it's properly indexed
        if [[ ! -f "${vcf_gz}.tbi" ]]; then
            bgzip -c <(cat "$bam" | lofreq call -f "$REF") > "$vcf_gz" 2>/dev/null || true
            tabix -p vcf "$vcf_gz"
        fi
    fi
done

# Create collapsed.tsv with all samples' variants
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${SAMPLES[@]}"; do
        vcf="$RESULTS_DIR/${sample}.vcf.gz"
        if [[ -f "$vcf" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AD]\n' "$vcf" | \
            awk -F'\t' -v sample="$sample" '
                NF >= 5 {
                    chrom = $1; pos = $2; ref = $3; alt = $4; ad = $5;
                    if (NF > 5) {
                        split(ad, alts, ",");
                        total = 0; for (i in alts) total += alts[i];
                        af = (total > 0) ? alts[1] / total : 0;
                    } else {
                        af = 0;
                    }
                    printf "%s\t%s\t%s\t%s\t%s\t%.6f\n", sample, chrom, pos, ref, alt, af;
                }'
        fi
    done | sort -t$'\t' -k1,1 -k2,2n -k4,4
} > "$RESULTS_DIR/collapsed.tsv"