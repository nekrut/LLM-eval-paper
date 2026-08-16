#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Index reference if not already indexed
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Function to process a sample given R1 and R2 fastq files
process_sample() {
    local base=$1
    local r1=$2
    local r2=$3
    local out_prefix="results/${base}"

    # Skip if BAM already exists (idempotent)
    if [ -f "${out_prefix}.bam" ]; then
        return 0
    fi

    # Align with bwa mem, sort and index with samtools
    bwa mem data/ref/chrM.fa "$(seqkit view -p gz -1 "$r1")" "$(seqkit view -p gz -2 "$r2")" \
        | samtools view -b -o "${out_prefix}.bam" -
    samtools sort -o "${out_prefix}.sorted.bam" "${out_prefix}.bam"
    samtools index "${out_prefix}.sorted.bam"

    # Generate VCF with lofreq
    lofreq variant \
        --bam "${out_prefix}.sorted.bam" \
        --ref data/ref/chrM.fa \
        --output "${out_prefix}.vcf.gz" \
        --min-QUAL 30 \
        --min-count 2

    # Index VCF with tabix
    bgzip -c "${out_prefix}.vcf.gz" > "${out_prefix}.vcf.gz.tmp"
    mv "${out_prefix}.vcf.gz.tmp" "${out_prefix}.vcf.gz"
    tabix -p vcf "${out_prefix}.vcf.gz"

    # Extract VCF entries with SnpSift
    java -jar "$(which snpsift.jar)" effect \
        -v \
        -region chrM \
        -format vcf \
        -o /dev/stdout \
        "${out_prefix}.vcf.gz" \
        | grep -v "^#" > "${out_prefix}.snpEff.vcf"

    # Extract fields and compute allele frequency
    awk 'BEGIN{FS="\t"; OFS="\t"} 
         NR==1 {print "sample","chrom","pos","ref","alt","af"}
         {
            split($5, a, ",");
            split(a[2], b, "|");
            ref=b[1]; alt=b[2];
            pos=$2; chrom=$1;
            af = (b[4] + b[6]) / 2;
            print "'"${base}"'",chrom,pos,ref,alt,af
         }' "${out_prefix}.snpEff.vcf" > "${out_prefix}_tmp.tsv"

    # Append to collapsed.tsv
    cat "${out_prefix}_tmp.tsv"
}

# Process each sample pair
process_sample "M117-bl"  data/raw/M117-bl_1.fq.gz  data/raw/M117-bl_2.fq.gz
process_sample "M117-ch"  data/raw/M117-ch_1.fq.gz    data/raw/M117-ch_2.fq.gz
process_sample "M117C1-bl" data/raw/M117C1-bl_1.fq.gz data/raw/M117C1-bl_2.fq.gz
process_sample "M117C1-ch"  data/raw/M117C1-ch_1.fq.gz   data/raw/M117C1-ch_2.fq.gz

# Collapse all per-sample VCF-derived rows into collapsed.tsv
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for f in results/*_tmp.tsv; do
        cat "$f"
    done
} > results/collapsed.tsv

# Cleanup temporary files (optional, safe to rerun)
rm -f results/*_tmp.tsv results/*.vcf.gz.tmp results/*.snpEff.vcf results/*.sorted.bam results/*.bam results/*.bai || true

exit 0