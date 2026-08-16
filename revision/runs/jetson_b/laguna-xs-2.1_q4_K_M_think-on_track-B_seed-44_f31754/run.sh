#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW="data/raw"
RESULTS="results"

mkdir -p "$RESULTS"

# Check if reference is already indexed by looking for .bwt file
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
    bam="$RESULTS/${sample}.bam"
    vcf_gz="$RESULTS/${sample}.vcf.gz"
    
    # Skip if outputs already exist (idempotent)
    if [[ -f "$bam" && -f "$vcf_gz" ]]; then
        continue
    fi
    
    # Align with bwa mem, pipe to samtools for sorting and marking duplicates
    bwa mem -t "$THREADS" "$REF" "${RAW}/${sample}_1.fq.gz" "${RAW}/${sample}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$bam" -
    
    # Mark duplicates and index BAM
    tmp_bam="${bam}.tmp"
    samtools markdup -r "$bam" "$tmp_bam"
    mv "$tmp_bam" "$bam"
    samtools index "$bam"
    
    # Call variants with lofreq, compress with bgzip and index with tabix
    lofreq call -f "$REF" -b "$bam" --verbose | \
        bcftools view -Ov -o "${RESULTS}/${sample}.vcf" && \
        bgzip -c "${RESULTS}/${sample}.vcf" > "$vcf_gz" && \
        tabix -p vcf "$vcf_gz" && \
        rm -f "${RESULTS}/${sample}.vcf"
done

# Create collapsed.tsv with all variants from all samples
echo -e "sample\tchrom\tpos\tref\talt\taf" > "$RESULTS/collapsed.tsv"

for sample in "${samples[@]}"; do
    vcf_gz="$RESULTS/${sample}.vcf.gz"
    
    # Extract variant info and calculate AF, append to collapsed.tsv
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AD]\n' "$vcf_gz" | \
        awk -F'\t' -v sample="$sample" '
        {
            chrom=$1; pos=$2; ref=$3; alt=$4
            if (NF > 4) {
                ad_ref=0; ad_alt=0
                for (i=5; i<=NF; i++) {
                    split($i, a, ",")
                    ad_ref+=a[1]; ad_alt+=a[2]
                }
                if ((ad_ref + ad_alt) > 0) {
                    af = ad_alt / (ad_ref + ad_alt)
                    printf "%s\t%s\t%s\t%s\t%.6f\n", sample, chrom, pos, ref, alt, af
                }
            }
        }' >> "$RESULTS/collapsed.tsv"
done

exit 0